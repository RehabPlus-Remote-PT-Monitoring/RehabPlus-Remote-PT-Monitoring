<?php

namespace App\Http\Controllers;

use App\Services\Notice\StaffNoticeService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;

/** Opening a notice from the bell: it's marked read, then the person goes to its appointment. */
class NoticeController extends Controller
{
    public function __construct(private StaffNoticeService $notices)
    {
    }

    public function open(Request $request, string $id): RedirectResponse
    {
        $notice = $this->notices->markRead($id, $request->user()->id);
        abort_unless($notice, 404);

        if (! empty($notice['appointmentId'])) {
            return redirect()->route('appointments.show', $notice['appointmentId']);
        }

        return redirect()->route('appointments.index');
    }
}
