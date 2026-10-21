local autoimg = require "commands.autoimg"
local link_preview = require "functions.link_preview"

-- for functions within this file
local detection = {}

-- for local connections
local _connections = {}

-- debug logging
-- resource intensive, not intended for end user usage ofc
local function log(label, value)
    if EVIL_DEBUG_VARIABLE then
        c2.log(
            c2.LogLevel.Info,
            "detection.lua/" .. label .. ": " .. tostring(value)
        )
    end
end

-- trim punctuation stuck to the end of the url
-- keep a ")" if the link itself opened it (wikipedia titles do this)
local function trim_url(candidate)
    local url = candidate:gsub("[%.%,%!%?%;:]+$", "")
    while url:sub(-1) == ")" do
        local opens = select(2, url:gsub("%(", ""))
        local closes = select(2, url:gsub("%)", ""))
        if closes <= opens then break end
        url = url:sub(1, -2):gsub("[%.%,%!%?%;:]+$", "")
    end
    return url
end

local fetch_urls = function(text)
    local urls = {}
    local _seen = {}

    -- image rendering candidates (URLs)
    -- find the URLs and trim text around
    -- also use gmatch() instead of match()
    for candidate in text:gmatch("https?://[%w%-%._~:/%?#%[%]@!$&'()*+,;=%%]+") do
        local url = trim_url(candidate)
        if url ~= ""
            and not _seen[url] then
            _seen[url] = true
            urls[#urls + 1] = url
        end
    end
    return urls
end

-- "bake" the message containing the image's URL
local function assemble(_message, image_urls)
    local elements = {}
    local _source = _message:elements()

    for i = 1, #_source do
        elements[#elements + 1] = _source[i]
    end

    -- place the images contained each in a new line
    for _, image_url in ipairs(image_urls or {}) do
        if type(image_url) == "string" and image_url ~= "" then
            elements[#elements + 1] = {
                type = "linebreak",
                flags = c2.MessageElementFlag.AlwaysShow,
            }
            elements[#elements + 1] = {
                type = "image",
                image = c2.Image.from_url(image_url, IMAGE_SCALE),
                flags = c2.MessageElementFlag.AlwaysShow,
            }
        end
    end

    -- the baked message
    -- yes it has to be something new
    -- whatever
    return c2.Message.new({
        flags = _message.flags,
        id = _message.id,
        search_text = _message.search_text,
        message_text = _message.message_text,
        login_name = _message.login_name,
        display_name = _message.display_name,
        localized_name = _message.localized_name,
        user_id = _message.user_id,
        channel_name = _message.channel_name,
        username_color = _message.username_color,
        server_received_time = _message.server_received_time,
        highlight_color = _message.highlight_color,
        elements = elements
    })
end

local function replace_with_images(channel, handle, _message, image_urls, text)
    -- block the handler here
    -- the new message still has the same text, so it would get scanned again otherwise
    handle:block()
    local replace_ok, replace_error = pcall(function()
        local replacement = assemble(_message, image_urls)
        log("message_text", text)
        channel:replace_message(_message, replacement)
    end)
    handle:unblock()
    if not replace_ok then
        log("replace_message error", replace_error)
    end
end

-- attach a message handler on all channels
function detection.attach(channel)
    if _connections[channel] then return end
    local handle
    local ok, result = pcall(function()
        return channel:on_message_appended(function(_message, override_flags)
            if not _message then return end
            local text_ok, text = pcall(function()
                return _message.message_text
            end)

            if not text_ok or type(text) ~= "string" then
                log("stopping at", "message_text unavailable or not a string")
                return
            end

            local urls = fetch_urls(text)

            if #urls == 0 then return end

            local pending = 0
            for _, url in ipairs(urls) do
                if not link_preview.is_direct_image(url) then
                    pending = pending + 1
                end
            end

            -- image files can go in right away
            -- page links have to wait for the resolver first
            if pending == 0 then
                replace_with_images(channel, handle, _message, urls, text)
                return
            end

            local resolved = {}
            for i, url in ipairs(urls) do
                if link_preview.is_direct_image(url) then
                    resolved[i] = url
                end
            end

            local function finish_one()
                pending = pending - 1
                if pending > 0 then return end

                local image_urls = {}
                for i = 1, #urls do
                    local image_url = resolved[i]
                    if type(image_url) == "string" and image_url ~= "" then
                        image_urls[#image_urls + 1] = image_url
                    end
                end
                if #image_urls == 0 then return end

                replace_with_images(channel, handle, _message, image_urls, text)
            end

            for i, url in ipairs(urls) do
                if not link_preview.is_direct_image(url) then
                    link_preview.resolve(url, function(thumbnail)
                        resolved[i] = thumbnail
                        finish_one()
                    end)
                end
            end
        end)
    end)

    if not ok then
        log("registration error", result)
        return
    end

    handle = result
    _connections[channel] = handle
end

return detection
