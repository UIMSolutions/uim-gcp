module app;

import std.conv : to;
import std.datetime : Clock;
import std.string : fromStringz;
import core.stdc.stdlib : getenv;
import vibe.vibe;
import uim.framework;

void main()
{
    auto settings = new HTTPServerSettings;
    settings.port = readPort();
    settings.bindAddresses = ["0.0.0.0"];

    auto router = new URLRouter;

    router.get("/", &index);
    router.get("/healthz", &healthz);
    router.get("/readyz", &readyz);

    auto listener = listenHTTP(settings, router);
    scope (exit) listener.stopListening();

    logInfo("uim-appengine-service started on port %d", settings.port);
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
    auto payload = Json([
        "service": Json("uim-appengine-service"),
        "framework": Json("uim-framework + vibe.d"),
        "timestamp": Json(Clock.currTime.toISOExtString())
    ]);

    res.writeJsonBody(payload);
}

private void healthz(HTTPServerRequest req, HTTPServerResponse res)
{
    auto payload = Json([
        "status": Json("ok")
    ]);

    res.writeJsonBody(payload);
}

private void readyz(HTTPServerRequest req, HTTPServerResponse res)
{
    auto payload = Json([
        "status": Json("ready"),
        "uim": Json("enabled")
    ]);

    res.writeJsonBody(payload);
}
