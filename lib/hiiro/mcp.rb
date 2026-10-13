# frozen_string_literal: true

# The h mcp implementation: MCPRegistry (SQLite records), MCPCatalog and
# MCPCommands (SDK discovery, schemas, calls), and MCPSync (HTTP-only export).
# Commands outside the gem load it with `require 'hiiro/mcp'`.
require 'hiiro'
require_relative 'mcp/registry'
require_relative 'mcp/catalog'
require_relative 'mcp/sync'
