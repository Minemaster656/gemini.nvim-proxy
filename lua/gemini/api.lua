local uv = vim.loop or vim.uv

local M = {}

local function get_api_base()
  if M.api_base then
    return "https://" .. M.api_base .. "/v1beta/models/"
  end
  
  local env_base = os.getenv("GEMINI_API_BASE")
  if env_base then
    return "https://" .. env_base .. "/v1beta/models/"
  end
  
  return "https://generativelanguage.googleapis.com/v1beta/models/"
end

M.config = {
  api_base = nil
}

M.setup = function(opts)
  opts = opts or {}
  M.config.api_base = opts.api_base
end

-- local API = "https://generativelanguage.googleapis.com/v1beta/models/";

M.MODELS = {
  GEMINI_FLASH_LATEST = 'gemini-flash-latest',
  GEMINI_2_5_PRO = 'gemini-2.5-pro',
  GEMINI_2_5_FLASH = 'gemini-2.5-flash',
  GEMINI_2_5_FLASH_LITE = 'gemini-2.5-flash-lite',
  GEMINI_2_0_FLASH = 'gemini-2.0-flash',
  GEMINI_2_0_FLASH_LITE = 'gemini-2.0-flash-lite',
}

M.gemini_generate_content = function(user_text, system_text, model_name, generation_config, callback)
  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    return ''
  end

  local api = get_api_base() .. model_name .. ':generateContent?key=' .. api_key
  local contents = {
    {
      parts = {
        {
          text = user_text
        }
      }
    }
  }
  local data = {
    contents = contents,
    generationConfig = generation_config,
  }
  if system_text then
    data.systemInstruction = {
      parts = {
        {
          text = system_text,
        }
      }
    }
  end

  local json_text = vim.json.encode(data)
  local cmd = { 'curl', '-X', 'POST', api, '-H', 'Content-Type: application/json', '--data-binary', '@-' }
  local opts = { stdin = json_text }
  if callback then
    return vim.system(cmd, opts, callback)
  else
    return vim.system(cmd, opts)
  end
end

M.gemini_generate_content_stream = function(user_text, model_name, generation_config, callback)
  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    return
  end

  if not callback then
    return
  end

  local api = get_api_base() .. model_name .. ':streamGenerateContent?alt=sse&key=' .. api_key
  local data = {
    contents = {
      {
        parts = {
          {
            text = user_text
          }
        }
      }
    },
    generationConfig = generation_config,
  }
  local json_text = vim.json.encode(data)

  local stdin = uv.new_pipe()
  local stdout = uv.new_pipe()
  local stderr = uv.new_pipe()
  local options = {
    stdio = { stdin, stdout, stderr },
    args = { api, '-X', 'POST', '-s', '-H', 'Content-Type: application/json', '-d', json_text }
  }

  uv.spawn('curl', options, function(code, _)
    print("gemini chat finished exit code", code)
  end)

  local streamed_data = ''
  uv.read_start(stdout, function(err, data)
    if not err and data then
      streamed_data = streamed_data .. data

      local start_index = string.find(streamed_data, 'data:')
      local end_index = string.find(streamed_data, '\r')
      local json_text = ''
      while start_index and end_index do
        if end_index >= start_index then
          json_text = string.sub(streamed_data, start_index + 5, end_index - 1)
          callback(json_text)
        end
        streamed_data = string.sub(streamed_data, end_index + 1)
        start_index = string.find(streamed_data, 'data:')
        end_index = string.find(streamed_data, '\r')
      end
    end
  end)
end

return M
