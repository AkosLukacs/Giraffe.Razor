module GiraffeRazorSample

open System
open System.IO
open System.Threading
open Microsoft.AspNetCore
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.AspNetCore.Http
open Microsoft.AspNetCore.Http.Features
open Microsoft.Extensions.Logging
open Microsoft.Extensions.DependencyInjection
open Giraffe
open Giraffe.Razor

// ---------------------------------
// Models
// ---------------------------------

[<CLIMutable>]
type Person =
    {
        Name : string
    }

// ---------------------------------
// Web app
// ---------------------------------

let bytesToKbStr (bytes : int64) =
    sprintf "%ikb" (bytes / 1024L)

let displayFileInfos (files : IFormFileCollection) =
    files
    |> Seq.fold (fun acc file ->
        sprintf "%s\n\n%s\n%s" acc file.FileName (bytesToKbStr file.Length)) ""
    |> text

let smallFileUploadHandler =
    fun (next : HttpFunc) (ctx : HttpContext) ->
        task {
            return!
                (match ctx.Request.HasFormContentType with
                | false -> text "Bad request" |> RequestErrors.badRequest
                | true  -> ctx.Request.Form.Files |> displayFileInfos) next ctx
        }

let largeFileUploadHandler =
    fun (next : HttpFunc) (ctx : HttpContext) ->
        task {
            let formFeature = ctx.Features.Get<IFormFeature>()
            let! form = formFeature.ReadFormAsync CancellationToken.None
            return! (form.Files |> displayFileInfos) next ctx
        }

let slowserver (iterCnt: int) =
    // chew up some CPU.
    for i in [1..10000] do
        for i in [1..iterCnt] do
            do "Hello".Contains("H") |> ignore
            // we don't care about the answer!
    razorHtmlView "index" ()

let webApp =
    choose [
        GET >=>
            choose [
                route  "/"       >=> razorHtmlView "index" ()
                route  "/razor"  >=> razorView "text/html" "Hello" ()
                route  "/person" >=> razorHtmlView "Person" { Name = "Razor" }
                route  "/upload" >=> razorHtmlView "FileUpload" ()
                route  "/slowview"   >=> razorHtmlView "SlowView" ()
                routef  "/slowserver/%i" slowserver
            ]
        POST >=>
            choose [
                route "/small-upload" >=> smallFileUploadHandler
                route "/large-upload" >=> largeFileUploadHandler
            ]
        text "Not Found" |> RequestErrors.notFound ]

// ---------------------------------
// Error handler
// ---------------------------------

let errorHandler (ex : Exception) (logger : ILogger) =
    logger.LogError(EventId(), ex, "An unhandled exception has occurred while executing the request.")
    clearResponse >=> ServerErrors.INTERNAL_ERROR (text ex.Message)

// ---------------------------------
// Main
// ---------------------------------

let configureApp (app : IApplicationBuilder) =
    app.UseGiraffeErrorHandler(errorHandler)
       .UseMiniProfiler()
       .UseStaticFiles()
       .UseAuthentication()
       .UseGiraffe webApp

let configureServices (services : IServiceCollection) =
    let sp  = services.BuildServiceProvider()
    let env = sp.GetService<IHostingEnvironment>()
    let viewsPath = Path.Combine(env.ContentRootPath, "Views")
    services.AddRazorEngine(viewsPath)
            .AddMiniProfiler()
    |> ignore

let configureLogging (loggerBuilder : ILoggingBuilder) =
    loggerBuilder.AddFilter(fun lvl -> lvl.Equals LogLevel.Error)
                 .AddConsole()
                 .AddDebug() |> ignore

[<EntryPoint>]
let main _ =
    let contentRoot = Directory.GetCurrentDirectory()
    let webRoot     = Path.Combine(contentRoot, "WebRoot")
    WebHost.CreateDefaultBuilder()
        .UseWebRoot(webRoot)
        .Configure(Action<IApplicationBuilder> configureApp)
        .ConfigureServices(configureServices)
        .ConfigureLogging(configureLogging)
        .Build()
        .Run()
    0