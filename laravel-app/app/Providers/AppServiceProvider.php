<?php

namespace App\Providers;

use App\Auth\FirebaseUserProvider;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Staff sign in with Firebase Auth; profiles and roles come from Firestore users/{uid}.
        Auth::provider('firebase', fn ($app) => $app->make(FirebaseUserProvider::class));
    }
}
