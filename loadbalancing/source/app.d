module app;

import std.conv : to;
import std.datetime : Clock;
import std.string : fromStringz, splitLines, strip, toLower;
import core.stdc.stdlib : getenv;
import core.sync.mutex : Mutex;
import vibe.vibe;
import uim.framework;

struct Backend
{
    string id;
    string url;
    size_t weight;
    bool healthy;
    long registeredAt;
}

__gshared Backend[] backends;
__gshared Mutex backendsMutex;
__gshared size_t rrIndex;
__gshared ulong backendSeq;

void main()
{
    backendsMutex = new Mutex;

    auto settings = new HTTPServerSettings;
    settings.port = readPort();
    settings.bindAddresses = ["0.0.0.0"];

    auto router = new URLRouter;
    router.get("/", &index);
    router.get("/healthz", &healthz);
    router.get("/readyz", &readyz);
    router.post("/v1/backends", &registerBackend);
    router.get("/v1/backends", &listBackends);
    router.post("/v1/backends/*/health", &setBackendHealthByPath);
    router.get("/v1/next", &nextBackend);
    router.post("/v1/simulate", &simulateDistribution);

    auto listener = listenHTTP(settings, router);
    scope (exit) listener.stopListening();

    logInfo("uim-loadbalancing-service started on port %d", settings.port);
    runApplication();
}

private ushort readPort()
{
    if (auto p = getenv("PORT"))
    {
        try
        {
            auto parsed = to!ushort(fromStringz(p));
            if (parsed > 0)
            {
                return parsed;
            }
        }
        catch (Exception)
        {}
    }

    return 8080;
}

private void index(HTTPServerRequest req, HTTPServerResponse res)
{
    size_t backendCount;
    size_t healthyCount;

    synchronized (backendsMutex)
    {
        backendCount = backends.length;
        foreach (b; backends)
        {
            if (b.healthy)
            {
                healthyCount++;
            }
        }
    }

    res.writeJsonBody(Json([
        "service": Json("uim-loadbalancing-service"),
        "mode": Json("cloud-load-balancing-like"),
        "framework": Json("uim-framework + vibe.d"),
        "backendCount": Json(backendCount),
        "healthyBackendCount": Json(healthyCount),
        "timestamp": Json(Clock.currTime.toISOExtString())
    ]));
}

private void healthz(HTTPServerRequest req, HTTPServerResponse res)
{
    res.writeJsonBody(Json([
        "status": Json("ok")
    ]));
}

private void readyz(HTTPServerRequest req, HTTPServerResponse res)
{
    bool ready;

    synchronized (backendsMutex)
    {
        foreach (b; backends)
        {
            if (b.healthy)
            {
                ready = true;
                break;
            }
        }
    }

    res.statusCode = ready ? HTTPStatus.ok : HTTPStatus.serviceUnavailable;
    res.writeJsonBody(Json([
        "status": Json(ready ? "ready" : "not-ready"),
        "required": Json("at least one healthy backend")
    ]));
}

private void registerBackend(HTTPServerRequest req, HTTPServerResponse res)
{
    auto params = parseBodyKeyValue(req.bodyReader.readAllUTF8());

    if (!("url" in params) || strip(params["url"]).length == 0)
    {
        res.statusCode = HTTPStatus.badRequest;
        res.writeJsonBody(Json([
            "error": Json("missing required field: url")
        ]));
        return;
    }

    size_t weight = 1;
    if ("weight" in params)
    {
        weight = parsePositiveSize(params["weight"], 1);
    }

    bool healthy = true;
    if ("healthy" in params)
    {
        healthy = parseBool(params["healthy"], true);
    }

    Backend backend;
    backend.id = newBackendId();
    backend.url = strip(params["url"]);
    backend.weight = weight;
    backend.healthy = healthy;
    backend.registeredAt = Clock.currTime.toUnixTime();

    synchronized (backendsMutex)
    {
        backends ~= backend;
    }

    res.statusCode = HTTPStatus.created;
    res.writeJsonBody(Json([
        "backendId": Json(backend.id),
        "url": Json(backend.url),
        "weight": Json(backend.weight),
        "healthy": Json(backend.healthy)
    ]));
}

private string newBackendId()
{
    synchronized (backendsMutex)
    {
        backendSeq++;
        return "backend-" ~ to!string(backendSeq);
    }
}

private void listBackends(HTTPServerRequest req, HTTPServerResponse res)
{
    Json[] items;

    synchronized (backendsMutex)
    {
        foreach (backend; backends)
        {
            items ~= Json([
                "backendId": Json(backend.id),
                "url": Json(backend.url),
                "weight": Json(backend.weight),
                "healthy": Json(backend.healthy),
                "registeredAt": Json(backend.registeredAt)
            ]);
        }
    }

    res.writeJsonBody(Json([
        "backends": Json(items)
    ]));
}

private void setBackendHealthByPath(HTTPServerRequest req, HTTPServerResponse res)
{
    auto path = req.requestPath.toString();
    auto prefix = "/v1/backends/";
    auto suffix = "/health";

    if (path.length <= prefix.length + suffix.length ||
        path[0 .. prefix.length] != prefix ||
        path[$ - suffix.length .. $] != suffix)
    {
        res.statusCode = HTTPStatus.notFound;
        return;
    }

    auto backendId = path[prefix.length .. $ - suffix.length];
    if (backendId.length == 0)
    {
        res.statusCode = HTTPStatus.notFound;
        return;
    }

    auto params = parseBodyKeyValue(req.bodyReader.readAllUTF8());
    if (!("healthy" in params))
    {
        res.statusCode = HTTPStatus.badRequest;
        res.writeJsonBody(Json([
            "error": Json("missing required field: healthy")
        ]));
        return;
    }

    auto newHealth = parseBool(params["healthy"], true);
    bool found;

    synchronized (backendsMutex)
    {
        foreach (ref backend; backends)
        {
            if (backend.id == backendId)
            {
                backend.healthy = newHealth;
                found = true;
                break;
            }
        }
    }

    if (!found)
    {
        res.statusCode = HTTPStatus.notFound;
        res.writeJsonBody(Json([
            "error": Json("backend not found"),
            "backendId": Json(backendId)
        ]));
        return;
    }

    res.writeJsonBody(Json([
        "backendId": Json(backendId),
        "healthy": Json(newHealth)
    ]));
}

private void nextBackend(HTTPServerRequest req, HTTPServerResponse res)
{
    Backend selected;
    if (!chooseNextBackend(selected))
    {
        res.statusCode = HTTPStatus.serviceUnavailable;
        res.writeJsonBody(Json([
            "error": Json("no healthy backends available")
        ]));
        return;
    }

    res.writeJsonBody(Json([
        "backendId": Json(selected.id),
        "url": Json(selected.url),
        "weight": Json(selected.weight),
        "healthy": Json(selected.healthy)
    ]));
}

private void simulateDistribution(HTTPServerRequest req, HTTPServerResponse res)
{
    auto params = parseBodyKeyValue(req.bodyReader.readAllUTF8());
    auto requestCount = parsePositiveSize(("requests" in params) ? params["requests"] : "100", 100);

    if (requestCount > 10000)
    {
        requestCount = 10000;
    }

    size_t[string] counts;

    foreach (_; 0 .. requestCount)
    {
        Backend selected;
        if (!chooseNextBackend(selected))
        {
            break;
        }

        counts[selected.id] = counts.get(selected.id, 0) + 1;
    }

    Json[] stats;
    foreach (id, count; counts)
    {
        stats ~= Json([
            "backendId": Json(id),
            "count": Json(count)
        ]);
    }

    res.writeJsonBody(Json([
        "requests": Json(requestCount),
        "distribution": Json(stats)
    ]));
}

private bool chooseNextBackend(out Backend selected)
{
    synchronized (backendsMutex)
    {
        size_t[] weighted;

        foreach (idx, backend; backends)
        {
            if (!backend.healthy)
            {
                continue;
            }

            auto repeatCount = backend.weight == 0 ? 1 : backend.weight;
            foreach (_; 0 .. repeatCount)
            {
                weighted ~= idx;
            }
        }

        if (weighted.length == 0)
        {
            return false;
        }

        auto slot = weighted[rrIndex % weighted.length];
        rrIndex++;
        selected = backends[slot];
        return true;
    }
}

private string[string] parseBodyKeyValue(string body)
{
    string[string] outMap;

    foreach (line; splitLines(body))
    {
        auto trimmed = strip(line);
        if (trimmed.length == 0)
        {
            continue;
        }

        auto sep = trimmed.countUntil("=");
        if (sep <= 0 || sep >= trimmed.length - 1)
        {
            continue;
        }

        auto key = toLower(strip(trimmed[0 .. sep]));
        auto value = strip(trimmed[sep + 1 .. $]);
        outMap[key] = value;
    }

    return outMap;
}

private bool parseBool(string value, bool defaultValue)
{
    auto v = toLower(strip(value));

    if (v == "1" || v == "true" || v == "yes" || v == "on")
    {
        return true;
    }

    if (v == "0" || v == "false" || v == "no" || v == "off")
    {
        return false;
    }

    return defaultValue;
}

private size_t parsePositiveSize(string value, size_t defaultValue)
{
    try
    {
        auto parsed = to!size_t(strip(value));
        return parsed == 0 ? defaultValue : parsed;
    }
    catch (Exception)
    {
        return defaultValue;
    }
}
