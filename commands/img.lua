local link_preview = require "functions.link_preview"

local function post_image(channel, url)
    channel:add_message(c2.Message.new({
        id = "inline-media",
        flags = c2.MessageFlag.System,
        elements = {
            {
                type = "image",
                image = c2.Image.from_url(url, IMAGE_SCALE),
                trailing_space = true,
                flags = c2.MessageElementFlag.EmoteImage,
            },
        },
    }))
end

c2.register_command("/img", function(ctx)
    -- get the arguments after the command
    -- start with an empty table
    local args = {}
    for i = 2, #ctx.words do
        args[#args + 1] = ctx.words[i]
    end

    local url = table.concat(args, " ")
    -- return usage
    if url == "" then
        ctx.channel:add_system_message(
            "Usage: /img <URL>"
        )
        return
    end

    -- this should be an option but not on this command
    --[[
    if not url:match("^https?://") then
        -- the url passed through the command should have a protocol
        ctx.channel:add_system_message(
            "the argument provided does not provide a protocol, which is required (http://, https://)"
        )
        return
    end
    ]] --

    -- page links need the resolver first
    -- anything else just gets loaded as is
    if url:match("^https?://") and not link_preview.is_direct_image(url) then
        link_preview.resolve(url, function(thumbnail)
            if type(thumbnail) ~= "string" or thumbnail == "" then
                ctx.channel:add_system_message(
                    "No preview found for that link"
                )
                return
            end
            post_image(ctx.channel, thumbnail)
        end)
        return
    end

    local scaled_url = url
        .. (url:find("?", 1, true) and "&" or "?")
        .. "chatterino_scale=" .. tostring(IMAGE_SCALE)

    post_image(ctx.channel, scaled_url)
end)
