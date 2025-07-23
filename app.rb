require 'sinatra'
require 'sinatra/json'
require 'json'
require 'httparty'
require 'dotenv/load'
require 'securerandom'
require_relative 'lib/gemini_cli_service'

# Optional requires - only load if environment variables are set
begin
  require 'google/cloud/firestore' if ENV['GOOGLE_CLOUD_PROJECT_ID']
rescue LoadError
  puts "Warning: google-cloud-firestore not available"
end

begin
  require 'octokit' if ENV['GITHUB_TOKEN']
rescue LoadError
  puts "Warning: octokit not available"
end

begin
  require 'line/bot' if ENV['LINE_CHANNEL_SECRET']
rescue LoadError
  puts "Warning: line-bot-api not available"
end

# Configure CORS
require 'rack/cors'
use Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: [:get, :post, :put, :delete, :options]
  end
end

# Configuration
configure do
  set :port, ENV['PORT'] || 4567
  set :bind, '0.0.0.0'
  
  # Initialize services
  set :firestore, Google::Cloud::Firestore.new(
    project_id: ENV['GOOGLE_CLOUD_PROJECT_ID']
  ) if ENV['GOOGLE_CLOUD_PROJECT_ID']
  
  set :github_client, Octokit::Client.new(access_token: ENV['GITHUB_TOKEN']) if ENV['GITHUB_TOKEN']
  
  set :line_client, Line::Bot::Client.new do |config|
    config.channel_secret = ENV['LINE_CHANNEL_SECRET']
    config.channel_token = ENV['LINE_CHANNEL_TOKEN']
  end if ENV['LINE_CHANNEL_SECRET'] && ENV['LINE_CHANNEL_TOKEN']
  
  # Initialize Gemini CLI service
  set :gemini_service, GeminiCliService.new
end

# Health check endpoint
get '/health' do
  json({ status: 'ok', timestamp: Time.now.iso8601 })
end

# GitHub webhook endpoint
post '/webhooks/github' do
  request.body.rewind
  payload_body = request.body.read
  
  # Verify webhook signature
  signature = 'sha256=' + OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new('sha256'),
    ENV['GITHUB_WEBHOOK_SECRET'],
    payload_body
  )
  
  halt 401 unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE_256'])
  
  payload = JSON.parse(payload_body)
  event_type = request.env['HTTP_X_GITHUB_EVENT']
  
  # Process GitHub events
  case event_type
  when 'issues'
    handle_github_issue(payload)
  when 'issue_comment'
    handle_github_comment(payload)
  when 'pull_request'
    handle_github_pull_request(payload)
  end
  
  json({ status: 'processed' })
end

# LINE webhook endpoint
post '/webhooks/line' do
  body = request.body.read
  signature = request.env['HTTP_X_LINE_SIGNATURE']
  
  unless settings.line_client.validate_signature(body, signature)
    halt 400
  end
  
  events = settings.line_client.parse_events_from(body)
  
  events.each do |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        handle_line_message(event)
      end
    end
  end
  
  json({ status: 'ok' })
end

# Task management endpoints
get '/tasks' do
  tasks = settings.firestore.collection('tasks').get.map(&:data)
  json(tasks)
end

post '/tasks' do
  task_data = JSON.parse(request.body.read)
  task_data['created_at'] = Time.now.iso8601
  task_data['status'] = 'pending'
  
  doc_ref = settings.firestore.collection('tasks').add(task_data)
  
  # Trigger AI agent processing
  process_task_async(doc_ref.document_id, task_data)
  
  json({ task_id: doc_ref.document_id, status: 'queued' })
end

get '/tasks/:id' do
  task = settings.firestore.collection('tasks').document(params[:id]).get
  halt 404 unless task.exists?
  
  json(task.data)
end

# Gemini CLI endpoints

# Start a new gemini-cli session
post '/gemini/sessions' do
  request.body.rewind
  data = JSON.parse(request.body.read)
  
  session_id = data['session_id'] || SecureRandom.uuid
  options = data['options'] || {}
  
  success = settings.gemini_service.start_process(session_id, options)
  
  if success
    json({
      success: true,
      session_id: session_id,
      message: "Gemini CLI session started"
    })
  else
    status 500
    json({
      success: false,
      error: "Failed to start gemini-cli process"
    })
  end
end

# Send command to gemini-cli session
post '/gemini/sessions/:session_id/command' do
  request.body.rewind
  data = JSON.parse(request.body.read)
  
  command = data['command']
  timeout = data['timeout'] || 30
  
  result = settings.gemini_service.send_command(params[:session_id], command, timeout: timeout)
  
  json(result)
end

# Send structured prompt to gemini-cli session
post '/gemini/sessions/:session_id/prompt' do
  request.body.rewind
  data = JSON.parse(request.body.read)
  
  prompt = data['prompt']
  context = data['context']
  timeout = data['timeout'] || 30
  
  result = settings.gemini_service.send_prompt(
    params[:session_id], 
    prompt, 
    context: context, 
    timeout: timeout
  )
  
  json(result)
end

# Get session status
get '/gemini/sessions/:session_id/status' do
  status_info = settings.gemini_service.process_status(params[:session_id])
  json(status_info)
end

# Stop gemini-cli session
delete '/gemini/sessions/:session_id' do
  success = settings.gemini_service.stop_process(params[:session_id])
  
  json({
    success: success,
    message: success ? "Session stopped" : "Failed to stop session"
  })
end

# List all active sessions
get '/gemini/sessions' do
  sessions = settings.gemini_service.list_processes
  json({ sessions: sessions })
end

# AI Agent execution endpoint (legacy)
post '/execute' do
  task_data = JSON.parse(request.body.read)
  
  # Execute gemini-cli with MCP
  result = execute_gemini_cli(task_data)
  
  json(result)
end

# Helper methods
def handle_github_issue(payload)
  return unless payload['action'] == 'labeled'
  
  # Check for dAIdalus trigger labels
  labels = payload['issue']['labels'].map { |l| l['name'] }
  return unless labels.include?('daidalus') || labels.include?('ai-assist')
  
  task_data = {
    type: 'github_issue',
    source: 'github',
    repository: payload['repository']['full_name'],
    issue_number: payload['issue']['number'],
    title: payload['issue']['title'],
    body: payload['issue']['body'],
    labels: labels,
    user: payload['issue']['user']['login']
  }
  
  queue_task(task_data)
end

def handle_github_comment(payload)
  return unless payload['action'] == 'created'
  
  comment_body = payload['comment']['body']
  return unless comment_body.include?('@dAIdalus')
  
  # Extract command from comment
  command = extract_command_from_comment(comment_body)
  
  task_data = {
    type: 'github_comment',
    source: 'github',
    repository: payload['repository']['full_name'],
    issue_number: payload['issue']['number'],
    comment_id: payload['comment']['id'],
    command: command,
    user: payload['comment']['user']['login']
  }
  
  queue_task(task_data)
end

def handle_github_pull_request(payload)
  return unless payload['action'] == 'opened' || payload['action'] == 'synchronize'
  
  # Check if PR has dAIdalus labels or mentions
  labels = payload['pull_request']['labels'].map { |l| l['name'] }
  body = payload['pull_request']['body'] || ''
  
  return unless labels.include?('daidalus') || body.include?('@dAIdalus')
  
  task_data = {
    type: 'github_pr',
    source: 'github',
    repository: payload['repository']['full_name'],
    pr_number: payload['pull_request']['number'],
    title: payload['pull_request']['title'],
    body: body,
    labels: labels,
    user: payload['pull_request']['user']['login']
  }
  
  queue_task(task_data)
end

def handle_line_message(event)
  message_text = event.message['text']
  return unless message_text.include?('@dAIdalus') || event.source.type == 'user'
  
  task_data = {
    type: 'line_message',
    source: 'line',
    user_id: event.source.user_id,
    message: message_text,
    reply_token: event['replyToken']
  }
  
  queue_task(task_data)
end

def queue_task(task_data)
  task_data['created_at'] = Time.now.iso8601
  task_data['status'] = 'pending'
  
  doc_ref = settings.firestore.collection('tasks').add(task_data)
  
  # Trigger async processing
  process_task_async(doc_ref.document_id, task_data)
end

def process_task_async(task_id, task_data)
  # In a real implementation, this would trigger Cloud Functions or Cloud Run
  # For now, we'll simulate async processing
  Thread.new do
    begin
      # Update task status
      settings.firestore.collection('tasks').document(task_id).update({
        status: 'processing',
        started_at: Time.now.iso8601
      })
      
      # Execute AI agent
      result = execute_gemini_cli(task_data)
      
      # Update task with result
      settings.firestore.collection('tasks').document(task_id).update({
        status: 'completed',
        completed_at: Time.now.iso8601,
        result: result
      })
      
      # Send feedback
      send_feedback(task_data, result)
      
    rescue => e
      # Handle errors
      settings.firestore.collection('tasks').document(task_id).update({
        status: 'failed',
        failed_at: Time.now.iso8601,
        error: e.message
      })
    end
  end
end

def execute_gemini_cli(task_data)
  # Create a temporary session for legacy execute endpoint
  session_id = SecureRandom.uuid
  
  begin
    # Start gemini-cli process
    success = settings.gemini_service.start_process(session_id, {
      interactive: true,
      model: task_data['model'] || 'gemini-pro'
    })
    
    unless success
      return {
        success: false,
        error: "Failed to start gemini-cli process",
        timestamp: Time.now.iso8601
      }
    end
    
    # Format task as prompt
    prompt = format_task_as_prompt(task_data)
    
    # Send prompt to gemini-cli
    result = settings.gemini_service.send_prompt(session_id, prompt, timeout: 60)
    
    # Clean up session
    settings.gemini_service.stop_process(session_id)
    
    if result[:error]
      {
        success: false,
        error: result[:error],
        timestamp: Time.now.iso8601
      }
    else
      {
        success: true,
        response: result[:response],
        task_type: task_data['type'],
        timestamp: Time.now.iso8601
      }
    end
    
  rescue => e
    # Ensure cleanup
    settings.gemini_service.stop_process(session_id)
    
    {
      success: false,
      error: e.message,
      timestamp: Time.now.iso8601
    }
  end
end

def format_task_as_prompt(task_data)
  case task_data['type']
  when 'github_issue'
    "Please help with this GitHub issue:\n\nTitle: #{task_data['title']}\n\nDescription: #{task_data['body']}\n\nRepository: #{task_data['repository']}"
  when 'github_comment'
    "Please execute this command from a GitHub comment:\n\nCommand: #{task_data['command']}\n\nRepository: #{task_data['repository']}"
  when 'line_message'
    "Please respond to this LINE message:\n\nMessage: #{task_data['message']}"
  else
    task_data.to_json
  end
end

def send_feedback(task_data, result)
  case task_data['source']
  when 'github'
    send_github_feedback(task_data, result)
  when 'line'
    send_line_feedback(task_data, result)
  end
end

def send_github_feedback(task_data, result)
  repo = task_data['repository']
  
  case task_data['type']
  when 'github_issue'
    settings.github_client.add_comment(
      repo,
      task_data['issue_number'],
      "🤖 dAIdalus processed your request: #{result[:message]}"
    )
  when 'github_comment'
    settings.github_client.add_comment(
      repo,
      task_data['issue_number'],
      "🤖 dAIdalus executed command: #{task_data['command']}\n\nResult: #{result[:message]}"
    )
  when 'github_pr'
    settings.github_client.add_comment(
      repo,
      task_data['pr_number'],
      "🤖 dAIdalus analyzed your PR: #{result[:message]}"
    )
  end
end

def send_line_feedback(task_data, result)
  message = {
    type: 'text',
    text: "🤖 dAIdalus: #{result[:message]}"
  }
  
  settings.line_client.reply_message(task_data['reply_token'], message)
end

def extract_command_from_comment(comment_body)
  # Extract command like "@dAIdalus /fix-typo" or "@dAIdalus help"
  match = comment_body.match(/@dAIdalus\s+([^\n\r]+)/)
  match ? match[1].strip : 'help'
end

# Start the server
if __FILE__ == $0
  Sinatra::Application.run!
end
