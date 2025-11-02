Rails.application.config.mcp = {
  base_url: ENV.fetch('MCP_BASE_URL', 'https://mcp.corazondeseda.lat'),
  api_key: ENV['MCP_SERVER_KEY'],
  enable_tools: true,
  log_requests: true
}
