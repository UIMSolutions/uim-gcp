module app;

import std.algorithm : min;
import std.conv : to;
import std.datetime : Clock;
import std.string : fromStringz, splitLines, strip, toUpper;
import std.uni : isWhite;
import core.stdc.stdlib : getenv;
import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.time : dur;
import vibe.vibe;
import uim.framework;

struct DataflowJob
{
    string id;
    string status;
    string input;
    long submittedAt;
    long completedAt;
    size_t lineCount;
    size_t wordCount;
    size_t byteCount;
    string outputPreview;
    string error;
}

__gshared DataflowJob[string] jobs;
__gshared Mutex jobsMutex;
__gshared string[] jobQueue;
__gshared bool workerRunning;
__gshared Thread[] workerThreads;
__gshared size_t workerCount;

void main()
{
    jobsMutex = new Mutex;
    workerCount = readWorkerCount();
    workerRunning = true;

    workerThreads.length = workerCount;
    foreach (i; 0 .. workerCount)
    {
        workerThreads[i] = new Thread(&jobWorkerLoop);
        workerThreads[i].start();
    }

    scope (exit)
    {
        synchronized (jobsMutex)
        {
            workerRunning = false;
        }

        foreach (worker; workerThreads)
        {
            if (worker !is null)
            {
                worker.join();
            }
        }
    }

    auto settings = new HTTPServerSettings;
    settings.port = readPort();
    settings.bindAddresses = ["0.0.0.0"];

    auto router = new URLRouter;
    router.get("/", &index);
    router.get("/healthz", &healthz);
    router.get("/readyz", &readyz);
    router.post("/v1/jobs", &submitJob);
    router.get("/v1/jobs", &listJobs);
    router.get("/v1/jobs/*", &getJobByPath);

    auto listener = listenHTTP(settings, router);
    scope (exit) listener.stopListening();

    logInfo("uim-dataflow-service started on port %d with %d workers", settings.port, cast(int)workerCount);
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

private size_t readWorkerCount()
{
    if (auto p = getenv("WORKER_COUNT"))
    {
        try
        {
            auto parsed = to!size_t(fromStringz(p));
            if (parsed > 0 && parsed <= 64)
            {
                return parsed;
            }
        }
        catch (Exception)
        {}
    }

    return 2;
}

private void index(HTTPServerRequest req, HTTPServerResponse res)
{
    auto payload = Json([
        "service": Json("uim-dataflow-service"),
        "mode": Json("dataflow-like"),
        "framework": Json("uim-framework + vibe.d"),
        "workerCount": Json(workerCount),
        "timestamp": Json(Clock.currTime.toISOExtString())
    ]);

    res.writeJsonBody(payload);
}

private void healthz(HTTPServerRequest req, HTTPServerResponse res)
{
    res.writeJsonBody(Json([
        "status": Json("ok")
    ]));
}

private void readyz(HTTPServerRequest req, HTTPServerResponse res)
{
    res.writeJsonBody(Json([
        "status": Json("ready"),
        "uim": Json("enabled"),
        "workerCount": Json(workerCount)
    ]));
}

private void submitJob(HTTPServerRequest req, HTTPServerResponse res)
{
    auto input = req.bodyReader.readAllUTF8();
    auto cleanInput = strip(input);

    if (cleanInput.length == 0)
    {
        res.statusCode = HTTPStatus.badRequest;
        res.writeJsonBody(Json([
            "error": Json("request body cannot be empty")
        ]));
        return;
    }

    auto now = Clock.currTime;
    auto jobId = "job-" ~ to!string(now.stdTime);

    DataflowJob job;
    job.id = jobId;
    job.status = "queued";
    job.input = cleanInput;
    job.submittedAt = now.toUnixTime();

    {
        synchronized (jobsMutex)
        {
            jobs[job.id] = job;
            jobQueue ~= job.id;
        }
    }

    res.statusCode = HTTPStatus.accepted;
    res.writeJsonBody(Json([
        "jobId": Json(jobId),
        "status": Json("queued"),
        "message": Json("job accepted")
    ]));
}

private void jobWorkerLoop()
{
    while (true)
    {
        string jobId;
        bool shouldStop;

        synchronized (jobsMutex)
        {
            shouldStop = !workerRunning && jobQueue.length == 0;

            if (jobQueue.length > 0)
            {
                jobId = jobQueue[0];
                if (jobQueue.length == 1)
                {
                    jobQueue.length = 0;
                }
                else
                {
                    jobQueue = jobQueue[1 .. $];
                }
            }
        }

        if (shouldStop)
        {
            break;
        }

        if (jobId.length == 0)
        {
            Thread.sleep(dur!"msecs"(100));
            continue;
        }

        processJob(jobId);
    }
}

private void processJob(string jobId)
{
    DataflowJob job;

    {
        synchronized (jobsMutex)
        {
            if (auto ptr = jobId in jobs)
            {
                (*ptr).status = "running";
                job = *ptr;
            }
            else
            {
                return;
            }
        }
    }

    try
    {
        auto lines = splitLines(job.input);
        size_t words = countWords(job.input);
        auto previewSize = min(cast(size_t)256, job.input.length);
        auto preview = toUpper(job.input[0 .. previewSize]);

        Thread.sleep(dur!"msecs"(250));

        synchronized (jobsMutex)
        {
            if (auto ptr = jobId in jobs)
            {
                (*ptr).lineCount = lines.length;
                (*ptr).wordCount = words;
                (*ptr).byteCount = job.input.length;
                (*ptr).outputPreview = preview;
                (*ptr).status = "done";
                (*ptr).completedAt = Clock.currTime.toUnixTime();
            }
        }
    }
    catch (Exception ex)
    {
        synchronized (jobsMutex)
        {
            if (auto ptr = jobId in jobs)
            {
                (*ptr).status = "failed";
                (*ptr).error = ex.msg;
                (*ptr).completedAt = Clock.currTime.toUnixTime();
            }
        }
    }
}

private size_t countWords(string text)
{
    bool inWord = false;
    size_t count;

    foreach (dchar ch; text)
    {
        if (isWhite(ch))
        {
            inWord = false;
        }
        else if (!inWord)
        {
            inWord = true;
            count++;
        }
    }

    return count;
}

private void listJobs(HTTPServerRequest req, HTTPServerResponse res)
{
    Json[] items;

    synchronized (jobsMutex)
    {
        foreach (id, job; jobs)
        {
            items ~= Json([
                "jobId": Json(id),
                "status": Json(job.status),
                "submittedAt": Json(job.submittedAt)
            ]);
        }
    }

    res.writeJsonBody(Json([
        "jobs": Json(items)
    ]));
}

private void getJobByPath(HTTPServerRequest req, HTTPServerResponse res)
{
    auto path = req.requestPath.toString();
    auto marker = "/v1/jobs/";
    if (path.length <= marker.length || path[0 .. marker.length] != marker)
    {
        res.statusCode = HTTPStatus.notFound;
        return;
    }

    auto jobId = path[marker.length .. $];
    if (jobId.length == 0)
    {
        res.statusCode = HTTPStatus.notFound;
        return;
    }

    DataflowJob job;
    bool found;
    synchronized (jobsMutex)
    {
        if (auto ptr = jobId in jobs)
        {
            job = *ptr;
            found = true;
        }
    }

    if (!found)
    {
        res.statusCode = HTTPStatus.notFound;
        res.writeJsonBody(Json([
            "error": Json("job not found"),
            "jobId": Json(jobId)
        ]));
        return;
    }

    res.writeJsonBody(Json([
        "jobId": Json(job.id),
        "status": Json(job.status),
        "submittedAt": Json(job.submittedAt),
        "completedAt": Json(job.completedAt),
        "lineCount": Json(job.lineCount),
        "wordCount": Json(job.wordCount),
        "byteCount": Json(job.byteCount),
        "outputPreview": Json(job.outputPreview),
        "error": Json(job.error)
    ]));
}
