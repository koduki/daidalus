#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

class GeminiInterfaceTest
  def initialize(base_url = 'http://localhost:4567')
    @base_url = base_url
  end

  def run_tests
    puts "🧪 Testing Gemini CLI Interface"
    puts "=" * 50
    
    # Test 1: Health check
    test_health_check
    
    # Test 2: Create session
    session_id = test_create_session
    return unless session_id
    
    # Test 3: Send command
    test_send_command(session_id)
    
    # Test 4: Send prompt
    test_send_prompt(session_id)
    
    # Test 5: Check status
    test_session_status(session_id)
    
    # Test 6: List sessions
    test_list_sessions
    
    # Test 7: Stop session
    test_stop_session(session_id)
    
    puts "\n✅ All tests completed!"
  end

  private

  def test_health_check
    puts "\n1. Testing health check..."
    
    response = make_request('GET', '/health')
    
    if response && response['status'] == 'ok'
      puts "   ✅ Health check passed"
    else
      puts "   ❌ Health check failed"
    end
  end

  def test_create_session
    puts "\n2. Testing session creation..."
    
    payload = {
      session_id: "test-#{Time.now.to_i}",
      options: {
        interactive: true,
        model: 'gemini-pro'
      }
    }
    
    response = make_request('POST', '/gemini/sessions', payload)
    
    if response && response['success']
      puts "   ✅ Session created: #{response['session_id']}"
      return response['session_id']
    else
      puts "   ❌ Session creation failed: #{response&.dig('error') || 'Unknown error'}"
      return nil
    end
  end

  def test_send_command(session_id)
    puts "\n3. Testing command sending..."
    
    payload = {
      command: "Hello, can you help me?",
      timeout: 10
    }
    
    response = make_request('POST', "/gemini/sessions/#{session_id}/command", payload)
    
    if response && response['success']
      puts "   ✅ Command sent successfully"
      puts "   📝 Response: #{response['response'][0..100]}..." if response['response']
    else
      puts "   ❌ Command failed: #{response&.dig('error') || 'Unknown error'}"
    end
  end

  def test_send_prompt(session_id)
    puts "\n4. Testing prompt sending..."
    
    payload = {
      prompt: "What is the capital of Japan?",
      context: "This is a geography question",
      timeout: 10
    }
    
    response = make_request('POST', "/gemini/sessions/#{session_id}/prompt", payload)
    
    if response && response['success']
      puts "   ✅ Prompt sent successfully"
      puts "   📝 Response: #{response['response'][0..100]}..." if response['response']
    else
      puts "   ❌ Prompt failed: #{response&.dig('error') || 'Unknown error'}"
    end
  end

  def test_session_status(session_id)
    puts "\n5. Testing session status..."
    
    response = make_request('GET', "/gemini/sessions/#{session_id}/status")
    
    if response && response['exists']
      puts "   ✅ Session status retrieved"
      puts "   📊 Alive: #{response['alive']}, PID: #{response['pid']}"
    else
      puts "   ❌ Session status failed"
    end
  end

  def test_list_sessions
    puts "\n6. Testing session listing..."
    
    response = make_request('GET', '/gemini/sessions')
    
    if response && response['sessions']
      puts "   ✅ Sessions listed: #{response['sessions'].length} active"
    else
      puts "   ❌ Session listing failed"
    end
  end

  def test_stop_session(session_id)
    puts "\n7. Testing session stop..."
    
    response = make_request('DELETE', "/gemini/sessions/#{session_id}")
    
    if response && response['success']
      puts "   ✅ Session stopped successfully"
    else
      puts "   ❌ Session stop failed: #{response&.dig('message') || 'Unknown error'}"
    end
  end

  def make_request(method, path, payload = nil)
    uri = URI("#{@base_url}#{path}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    
    case method
    when 'GET'
      request = Net::HTTP::Get.new(uri)
    when 'POST'
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request.body = payload.to_json if payload
    when 'DELETE'
      request = Net::HTTP::Delete.new(uri)
    end
    
    begin
      response = http.request(request)
      JSON.parse(response.body) if response.body
    rescue => e
      puts "   ⚠️  Request error: #{e.message}"
      nil
    end
  end
end

# Run tests if script is executed directly
if __FILE__ == $0
  tester = GeminiInterfaceTest.new
  tester.run_tests
end
