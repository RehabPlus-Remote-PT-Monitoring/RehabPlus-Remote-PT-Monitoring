<?php

namespace App\Providers;

use App\Auth\FirebaseUserProvider;
use App\Services\Firebase\FirebaseAdmin;
use App\Services\Firebase\FirebaseMetrics;
use App\Services\Firebase\FirebaseTransport;
use App\Services\Firebase\FirestoreClient;
use App\Services\Firebase\GoogleAccessToken;
use App\Services\User\StaffDirectory;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\View;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // One token, transport and client per request, so the token is fetched
        // once and every Firebase call lands in the same request metrics.
        $this->app->singleton(GoogleAccessToken::class);
        $this->app->scoped(FirebaseMetrics::class);
        $this->app->scoped(FirebaseTransport::class);
        $this->app->scoped(FirestoreClient::class);
        $this->app->scoped(FirebaseAdmin::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Staff sign in with Firebase Auth; profiles and roles come from Firestore users/{uid}.
        Auth::provider('firebase', fn ($app) => $app->make(FirebaseUserProvider::class));

        // The top bar shows the signed-in person's current name and photo, not the ones from login.
        View::composer('layouts.admin', function ($view) {
            $user = auth()->user();
            $directory = app(StaffDirectory::class);

            $view->with('viewer', $user === null ? null : [
                'name' => $directory->name($user->id, $user->name),
                'photoUrl' => $directory->photoUrl($user->id),
            ]);
        });

        // A query-string value as trimmed text. Anything that isn't a plain
        // string (e.g. ?search[]=x) counts as missing, instead of crashing a
        // page with "Array to string conversion".
        Request::macro('queryText', function (string $key, string $default = ''): string {
            /** @var Request $this */
            $value = $this->query($key);

            return is_string($value) ? trim($value) : $default;
        });
    }
}
