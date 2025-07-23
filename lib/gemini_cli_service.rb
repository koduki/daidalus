require 'open3'
require 'json'
require 'logger'

class GeminiCliService
  attr_reader :logger

  def initialize(logger: Logger.new(STDOUT))
    @logger = logger
    @processes = {}
  end

  # Start a new gemini-cli process
  def start_process(session_id, options = {})
    return false if @processes[session_id]

    begin
      # Build gemini-cli command
      cmd = build_gemini_cli_command(options)
      
      # Start process with Open3
      stdin, stdout, stderr, wait_thr = Open3.popen3(cmd)
      
      @processes[session_id] = {
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        thread: wait_thr,
        created_at: Time.now
      }
      
      logger.info "Started gemini-cli process for session #{session_id}"
      true
    rescue => e
      logger.error "Failed to start gemini-cli process: #{e.message}"
      false
    end
  end

  # Send command to gemini-cli process
  def send_command(session_id, command, timeout: 30)
    process = @processes[session_id]
    return { error: "No active process for session #{session_id}" } unless process

    begin
      # Send command to stdin
      process[:stdin].puts(command)
      process[:stdin].flush
      
      # Read response with timeout
      response = read_with_timeout(process[:stdout], timeout)
      
      {
        success: true,
        response: response,
        timestamp: Time.now.iso8601
      }
    rescue => e
      logger.error "Error sending command to gemini-cli: #{e.message}"
      {
        error: e.message,
        timestamp: Time.now.iso8601
      }
    end
  end

  # Send structured prompt to gemini-cli
  def send_prompt(session_id, prompt, context: nil, timeout: 30)
    # Format prompt for gemini-cli
    formatted_prompt = format_prompt(prompt, context)
    send_command(session_id, formatted_prompt, timeout: timeout)
  end

  # Stop gemini-cli process
  def stop_process(session_id)
    process = @processes[session_id]
    return false unless process

    begin
      # Close stdin to signal end
      process[:stdin].close unless process[:stdin].closed?
      
      # Wait for process to finish or kill it
      if process[:thread].join(5)
        logger.info "Gemini-cli process #{session_id} finished gracefully"
      else
        Process.kill('TERM', process[:thread].pid)
        logger.info "Terminated gemini-cli process #{session_id}"
      end
      
      # Close remaining streams
      process[:stdout].close unless process[:stdout].closed?
      process[:stderr].close unless process[:stderr].closed?
      
      @processes.delete(session_id)
      true
    rescue => e
      logger.error "Error stopping gemini-cli process: #{e.message}"
      false
    end
  end

  # Get process status
  def process_status(session_id)
    process = @processes[session_id]
    return { exists: false } unless process

    {
      exists: true,
      alive: process[:thread].alive?,
      created_at: process[:created_at],
      pid: process[:thread].pid
    }
  end

  # List all active processes
  def list_processes
    @processes.map do |session_id, process|
      {
        session_id: session_id,
        alive: process[:thread].alive?,
        created_at: process[:created_at],
        pid: process[:thread].pid
      }
    end
  end

  # Cleanup all processes
  def cleanup_all
    @processes.keys.each { |session_id| stop_process(session_id) }
  end

  private

  def build_gemini_cli_command(options)
    cmd = ['gemini-cli']
    
    # Add common options
    cmd << '--interactive' if options[:interactive]
    cmd << '--model' << options[:model] if options[:model]
    cmd << '--temperature' << options[:temperature].to_s if options[:temperature]
    cmd << '--max-tokens' << options[:max_tokens].to_s if options[:max_tokens]
    
    # Add MCP server options if specified
    if options[:mcp_servers]
      options[:mcp_servers].each do |server|
        cmd << '--mcp-server' << server
      end
    end
    
    cmd.join(' ')
  end

  def format_prompt(prompt, context = nil)
    if context
      "Context: #{context}\n\nPrompt: #{prompt}"
    else
      prompt
    end
  end

  def read_with_timeout(stream, timeout)
    result = ""
    
    # Use select to read with timeout
    ready = IO.select([stream], nil, nil, timeout)
    
    if ready
      # Read available data
      while IO.select([stream], nil, nil, 0.1)
        begin
          chunk = stream.read_nonblock(4096)
          result += chunk
        rescue IO::WaitReadable
          break
        rescue EOFError
          break
        end
      end
    end
    
    result.strip
  end
end
