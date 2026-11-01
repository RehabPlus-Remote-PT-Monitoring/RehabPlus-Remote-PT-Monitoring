<?php

namespace App\Http\Controllers;

use App\Services\User\UserService;
use Illuminate\View\View;

/** The Home page: clinic details (config/clinic.php), the staff board and awards. */
class HomeController extends Controller
{
    public function __construct(private UserService $users)
    {
    }

    public function index(): View
    {
        return view('home.index', [
            'clinic' => config('clinic'),
            'staff' => $this->users->board(),
        ]);
    }
}
