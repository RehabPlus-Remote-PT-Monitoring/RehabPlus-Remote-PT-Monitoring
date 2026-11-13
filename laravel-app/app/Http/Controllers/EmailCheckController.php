<?php

namespace App\Http\Controllers;

use App\Services\User\EmailAvailability;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** Live check on the Add Patient and staff account forms: is this email already taken? */
class EmailCheckController extends Controller
{
    public function __construct(private EmailAvailability $emails)
    {
    }

    public function show(Request $request): JsonResponse
    {
        $email = trim((string) $request->query('email', ''));

        if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            return response()->json(['available' => null, 'message' => '']);
        }

        $taken = $this->emails->isTaken($email);

        return response()->json([
            'available' => ! $taken,
            'message' => $taken ? EmailAvailability::TAKEN_MESSAGE : '',
        ]);
    }
}
