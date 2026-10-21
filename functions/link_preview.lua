local json = require "chatterino.json"

local link_preview = {}

local RESOLVER_URL = "https://braize.pajlada.com/chatterino/link_resolver/"

-- encode the whole url, slashes and colons included
-- otherwise braize just answers 404 page not found
local function percent_encode(value)
    return (value:gsub("[^%w%-%.~_]", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local IMAGE_EXTS = {
    png = true,
    jpg = true,
    jpeg = true,
    gif = true,
    webp = true,
    avif = true,
    bmp = true,
}

-- true when the path (before ? or #) already ends in an image extension
function link_preview.is_direct_image(url)
    if type(url) ~= "string" or url == "" then
        return false
    end

    local path = url:match("^[^?#]*") or url
    local ext = path:match("%.([%a%d]+)$")
    if not ext then
        return false
    end

    return IMAGE_EXTS[ext:lower()] == true
end

local function thumbnail_from_response(response)
    local ok, parsed = pcall(json.parse, response:data())
    if not ok or type(parsed) ~= "table" then
        return nil
    end

    local thumbnail = parsed.thumbnail
    if parsed.status == 200
        and type(thumbnail) == "string"
        and thumbnail ~= "" then
        return thumbnail
    end

    return nil
end

-- calls back with the thumbnail, or nil if there isn't one
-- don't add chatterino_scale on these, it breaks the proxied urls
function link_preview.resolve(url, callback)
    local done = false
    local function finish(thumbnail)
        if done then return end
        done = true
        callback(thumbnail)
    end

    local ok = pcall(function()
        local request = c2.HTTPRequest.create(
            c2.HTTPMethod.Get,
            RESOLVER_URL .. percent_encode(url)
        )
        request:set_timeout(30000)
        request:on_success(function(response)
            finish(thumbnail_from_response(response))
        end)
        request:on_error(function()
            finish(nil)
        end)
        request:execute()
    end)

    if not ok then
        finish(nil)
    end
end

return link_preview
