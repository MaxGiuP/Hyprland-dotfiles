pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import Quickshell;
import QtQuick;

/**
 * A service for interacting with various booru APIs.
 */
Singleton {
    id: root
    property Component booruResponseDataComponent: BooruResponseData {}

    signal tagSuggestion(string query, var suggestions)

    property string failMessage: Translation.tr("That didn't work. Tips:\n- Check your tags and NSFW settings\n- If you don't have a tag in mind, type a page number")
    property var responses: []
    property int runningRequests: 0
    property var defaultUserAgent: Config.options?.networking?.userAgent || "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
    property var providerList: Object.keys(providers).filter(provider => provider !== "system" && providers[provider].api)
    property var providers: 
    {
        "system": { "name": Translation.tr("System") },
        "wallhaven": {
            "name": "Wallhaven",
            "url": "https://wallhaven.cc",
            "api": "https://wallhaven.cc/api/v1/search",
            "description": Translation.tr("General wallpapers | Non-anime (categories=100)"),
            "mapFunc": (response) => {
                const purityToRating = (p) => p === "sfw" ? "s" : (p === "nsfw" ? "e" : "q");
                const arr = response.data ?? [];
                return arr.map(item => {
                    const w = Number(item.dimension_x || item.width || 0);
                    const h = Number(item.dimension_y || item.height || 0);
                    const tags = (item.tags || []).map(t => t.name).join(" ");
                    const rating = purityToRating(item.purity || "sfw");
                    const isNSFW = rating !== "s";
                    const path = item.path; // direct image
                    return {
                        "id": item.id,
                        "width": w,
                        "height": h,
                        "aspect_ratio": (w && h) ? (w / h) : 1,
                        "tags": tags,
                        "rating": rating,
                        "is_nsfw": isNSFW,
                        "md5": item.hash || "",
                        "preview_url": item.thumbs?.small || item.thumbs?.original || path,
                        "sample_url": item.thumbs?.original || path,
                        "file_url": path,
                        "file_ext": (path || "").split(".").pop(),
                        "source": item.url || path
                    };
                });
            },
            // Wallhaven has no “tag suggest” endpoint; we’ll just echo queries later.
            "tagSearchTemplate": null
        },
        "unsplash": {
            "name": "Unsplash",
            "url": "https://unsplash.com",
            "api": "https://api.unsplash.com/photos/random",
            "description": Translation.tr("Photography | Official API (requires access key)"),

            // Map Unsplash JSON -> your unified image shape
            "mapFunc": (response) => {
                const toArray = Array.isArray(response) ? response : [response]; // /random returns object or array (when &count=)
                return toArray.map(photo => {
                    const w = Number(photo.width || 0);
                    const h = Number(photo.height || 0);
                    const tags = (photo.tags || []).map(t => t.title).join(" ");
                    const full  = photo.urls?.full   || photo.urls?.regular || photo.urls?.raw;
                    const prev  = photo.urls?.small  || photo.urls?.thumb   || photo.urls?.regular || full;

                    return {
                        "id": photo.id,
                        "width": w,
                        "height": h,
                        "aspect_ratio": (w && h) ? (w / h) : 1,
                        "tags": tags,
                        "rating": "s",               // Unsplash content is SFW by policy
                        "is_nsfw": false,
                        "md5": "",
                        "preview_url": prev,         // small/preview
                        "sample_url": photo.urls?.regular || full,
                        "file_url": full,            // best for wallpaper
                        "file_ext": "jpg",           // Unsplash serves JPEG (don’t rely on extension in URL)
                        "source": photo.links?.html || ("https://unsplash.com/photos/" + photo.id)
                    };
                });
            },

            // No public tag-suggest endpoint
            "tagSearchTemplate": null
        },
    }
    property var currentProvider: Persistent.states.booru.provider

    function getWorkingImageSource(url) {
        if (url.includes('pximg.net')) {
            return `https://www.pixiv.net/en/artworks/${url.substring(url.lastIndexOf('/') + 1).replace(/_p\d+\.(png|jpg|jpeg|gif)$/, '')}`;
        }
        return url;
    }
    
    function setProvider(provider) {
        provider = provider.toLowerCase()
        if (providerList.indexOf(provider) !== -1) {
            Persistent.states.booru.provider = provider
            root.addSystemMessage(Translation.tr("Provider set to ") + providers[provider].name
                + (provider == "zerochan" ? Translation.tr(". Notes for Zerochan:\n- You must enter a color\n- Set your zerochan username in `sidebar.booru.zerochan.username` config option. You [might be banned for not doing so](https://www.zerochan.net/api#:~:text=The%20request%20may%20still%20be%20completed%20successfully%20without%20this%20custom%20header%2C%20but%20your%20project%20may%20be%20banned%20for%20being%20anonymous.)!") : ""))
        } else {
            root.addSystemMessage(Translation.tr("Invalid API provider. Supported: \n- ") + providerList.join("\n- "))
        }
    }

    function clearResponses() {
        responses = []
    }

    function addSystemMessage(message) {
        responses = [...responses, root.booruResponseDataComponent.createObject(null, {
            "provider": "system",
            "tags": [],
            "page": -1,
            "images": [],
            "message": `${message}`
        })]
    }

    function constructRequestUrl(tags, nsfw=true, limit=20, page=1) {
        var provider = providers[currentProvider]
        var baseUrl = provider.api
        var url = baseUrl
        var tagString = tags.join(" ")
        if (!nsfw && !(["zerochan", "waifu.im", "t.alcy.cc"].includes(currentProvider))) {
            if (currentProvider == "gelbooru") 
                tagString += " rating:general";
            else 
                tagString += " rating:safe";
        }
        var params = []
        // Tags & limit
        if (currentProvider === "zerochan") {
            params.push("c=" + tagString) // zerochan doesn't have search in api, so we use color
            params.push("l=" + limit)
            params.push("s=" + "fav")
            params.push("t=" + 1)
            params.push("p=" + page)
        }
        else if (currentProvider === "unsplash") {
            // Tags -> search query. Use commas or spaces; API uses space-delimited.
            var query = (tags && tags.length) ? tags.join(" ").trim() : "landscape nature wallpaper";

            // Unsplash /photos/random supports count (max 30), orientation, content_filter
            var params = [];
            params.push("orientation=landscape");
            params.push("content_filter=high");               // keep it clean
            var count = Math.max(1, Math.min(limit, 30));    // Unsplash max=30
            if (count > 1) params.push("count=" + count);
            if (query.length) params.push("query=" + encodeURIComponent(query));

            return providers.unsplash.api + "?" + params.join("&");
        }
        else {
            params.push("tags=" + encodeURIComponent(tagString))
            params.push("limit=" + limit)
            if (currentProvider == "gelbooru") {
                params.push("pid=" + page)
            }
            else {
                params.push("page=" + page)
            }
        }
        if (baseUrl.indexOf("?") === -1) {
            url += "?" + params.join("&")
        } else {
            url += "&" + params.join("&")
        }
        return url
    }

    function makeRequest(tags, nsfw=false, limit=20, page=1) {
        var url = constructRequestUrl(tags, nsfw, limit, page)
        console.log("[Booru] Making request to " + url)

        const newResponse = root.booruResponseDataComponent.createObject(null, {
            "provider": currentProvider,
            "tags": tags,
            "page": page,
            "images": [],
            "message": ""
        })

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    // console.log("[Booru] Raw response: " + xhr.responseText)
                    const provider = providers[currentProvider]
                    let response;
                    if (provider.manualParseFunc) {
                        response = provider.manualParseFunc(xhr.responseText)
                    } else {
                        response = JSON.parse(xhr.responseText)
                        response = provider.mapFunc(response)
                    }
                    // console.log("[Booru] Mapped response: " + JSON.stringify(response))
                    newResponse.images = response
                    newResponse.message = response.length > 0 ? "" : root.failMessage
                    
                } catch (e) {
                    console.log("[Booru] Failed to parse response: " + e)
                    newResponse.message = root.failMessage
                } finally {
                    root.runningRequests--;
                    root.responses = [...root.responses, newResponse]
                }
            }
            else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Request failed with status: " + xhr.status)
            }
        }

        try {
        if (currentProvider == "unsplash") {
            // Put your key somewhere in your config/state; pick one:
            // 1) Config.options.networking.unsplashAccessKey
            // 2) Config.options.unsplash.accessKey
            // 3) Persistent.states.unsplash.accessKey
            var key =
                (Config.options?.networking?.unsplashAccessKey) ||
                (Config.options?.unsplash?.accessKey) ||
                (Persistent.states?.unsplash?.accessKey) ||
                "";

            if (!key) {
                root.addSystemMessage(Translation.tr(
                    "Unsplash requires an access key. Set it in your config (e.g., Config.options.networking.unsplashAccessKey)."
                ))
            }
            xhr.setRequestHeader("Authorization", "Client-ID " + key);
            xhr.setRequestHeader("Accept-Version", "v1");
        } else if (currentProvider == "danbooru") {
            xhr.setRequestHeader("User-Agent", defaultUserAgent)
        } else if (currentProvider == "zerochan") {
            const ua = Config.options?.sidebar?.booru?.zerochan?.username
                ? `Desktop sidebar booru viewer - username: ${Config.options.sidebar.booru.zerochan.username}`
                : defaultUserAgent;
            xhr.setRequestHeader("User-Agent", ua)
        }

        root.runningRequests++;
        xhr.send()
        } catch (error) {
            console.log("[Unsplash] header/send error:", error)
        }
    }

    property var currentTagRequest: null
    function triggerTagSearch(query) {
        if (currentTagRequest) {
            currentTagRequest.abort();
        }

        var provider = providers[currentProvider]
        if (provider.fixedTags) {
            root.tagSuggestion(query, provider.fixedTags)
            return provider.fixedTags;
        } else if (!provider.tagSearchTemplate) {
            return
        }
        var url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query))

        var xhr = new XMLHttpRequest()
        currentTagRequest = xhr
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                currentTagRequest = null
                try {
                    // console.log("[Booru] Raw response: " + xhr.responseText)
                    var response = JSON.parse(xhr.responseText)
                    response = provider.tagMapFunc(response)
                    // console.log("[Booru] Mapped response: " + JSON.stringify(response))
                    root.tagSuggestion(query, response)
                } catch (e) {
                    console.log("[Booru] Failed to parse response: " + e)
                }
            }
            else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Booru] Request failed with status: " + xhr.status)
            }
        }

        try {
            // Required for danbooru
            if (currentProvider == "danbooru") {
                xhr.setRequestHeader("User-Agent", defaultUserAgent)
            }
            xhr.send()
        } catch (error) {
            console.log("Could not set User-Agent:", error)
        } 
    }
}

