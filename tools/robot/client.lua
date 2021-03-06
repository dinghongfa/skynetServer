package.cpath = package.cpath .. ";../../build/clualib/?.so"
package.path = package.path .. ";../../lualib/base/?.lua;../../skynet/lualib/?.lua;../../skynet/examples/?.lua"

local socket = require "clientsocket"
local tprint = require('extend').Table.print
local argparse = require "argparse"
local Robot = require 'robot'

local function init_argparse()
    local parser = argparse()
    parser:description("Cmd Client")

    parser:option("-a", "--host"):default("127.0.0.1"):description("Server IP")
    parser:option("-p", "--port"):default("7011"):description("Server Port"):convert(tonumber)
    parser:option("-s", "--script"):description("Script")
    return parser
end

local function main()
    local args = init_argparse():parse()
    local ip = Robot.host2ip(args.host)
    if not ip then
        error("host to ip fail")
    end
    local client = Robot.Robot:new(ip, args.port, {
        shield = {["GS2CHeartBeat"] = true, ["C2GSHeartBeat"] = true},
    })
    if args.script then
        client:fork(client.run_script, client, args.script)
    end
    local co = coroutine.create(
        function()
            client:start()
        end
    )

    while client.running do
        local ok, err = coroutine.resume(co)
        if not ok then
            print("client err:", err)
            break
        end
        socket.usleep(100000)
    end
end

main()
