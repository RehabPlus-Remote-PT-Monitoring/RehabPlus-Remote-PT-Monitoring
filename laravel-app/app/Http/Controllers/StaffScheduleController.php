<?php

namespace App\Http\Controllers;

use App\Helpers\StaffScheduleValidation;
use App\Services\StaffSchedule\ShiftConflictService;
use App\Services\StaffSchedule\StaffScheduleService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class StaffScheduleController extends Controller
{
    public function __construct(
        private StaffScheduleService $schedule,
        private ShiftConflictService $shifts,
    ) {
    }

    public function index(Request $request): View
    {
        return view('admin.schedule', $this->schedule->overview((int) $request->query('week_offset', 0)));
    }

    public function store(Request $request): RedirectResponse
    {
        $shift = StaffScheduleValidation::shift($request);

        if ($this->shifts->hasConflict($shift)) {
            return redirect()->route('schedule')->withInput()->with('error', 'Schedule conflict detected: this staff member already has a shift at that time, or the room is already assigned to another staff member.');
        }

        $this->schedule->addShift($shift);

        return redirect()->route('schedule')->with('success', 'Staff schedule added successfully.');
    }

    public function storeTimeOff(Request $request): RedirectResponse
    {
        $this->schedule->addTimeOff(StaffScheduleValidation::timeOff($request));

        return redirect()->route('schedule')->with('success', 'Time off entry added successfully.');
    }
}
