<?php

namespace App\Http\Controllers;

use Illuminate\View\View;

/** Footer pages on the welcome site (FAQ, policies, terms). Their titles come from config/clinic.php. */
class InfoPageController extends Controller
{
    public function show(string $page): View
    {
        $pages = config('clinic.info_pages');
        abort_unless(array_key_exists($page, $pages), 404);

        // A page with its own text, if one has been written; otherwise the "being prepared" page.
        $view = view()->exists("info.pages.{$page}") ? "info.pages.{$page}" : 'info.show';

        return view($view, ['title' => $pages[$page], 'clinic' => config('clinic')]);
    }
}
