<?php

use App\Http\Middleware\EnsureAuthenticated;
use App\Http\Middleware\EnsureRole;
use App\Services\Firebase\FirebaseException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'auth.rehab' => EnsureAuthenticated::class,
            'role' => EnsureRole::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Firebase is the data store, so an outage or a rejected write (e.g. an
        // email that already has an account) shouldn't be a 500. Forms go back
        // with the message; pages show a "try again" screen. Still reported.
        $exceptions->render(function (FirebaseException $e, Request $request) {
            if (! $request->isMethod('GET') && ! $request->expectsJson()) {
                return back()
                    ->withInput($request->except(['password', 'password_confirmation']))
                    ->with('error', $e->getMessage());
            }

            return response()->view('errors.firebase', ['message' => $e->getMessage()], 503);
        });
    })->create();
