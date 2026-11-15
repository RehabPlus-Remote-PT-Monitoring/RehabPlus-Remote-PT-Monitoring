<?php

namespace App\Http\Controllers;

use App\Auth\StaffUser;
use App\Helpers\StaffScheduleValidation;
use App\Services\StaffSchedule\ShiftConflictService;
use App\Services\StaffSchedule\StaffScheduleService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\View\View;

class StaffScheduleController extends Controller
{
    private const NOT_SCHEDULABLE = 'Only active therapists can be put on the schedule.';

    private const ONLY_OWN = 'Therapists can only add shifts and time off for themselves.';

    public function __construct(
        private StaffScheduleService $schedule,
        private ShiftConflictService $shifts,
    ) {
    }

    public function index(Request $request): View
    {
        $overview = $this->schedule->overview((int) $request->queryText('week_offset', '0'));

        // Everyone sees the whole schedule, but a therapist's forms only offer
        // their own name: they may change only their own shifts and time off.
        $overview['formStaff'] = $this->formStaff($request->user(), $overview['staffDirectory']);

        return view('admin.schedule', $overview);
    }

    public function store(Request $request): RedirectResponse
    {
        $input = StaffScheduleValidation::shift($request);

        if ($refused = $this->refuseOthersSchedule($request, $input['staff_id'], 'shift')) {
            return $refused;
        }

        $account = $this->schedule->schedulableAccount($input['staff_id']);
        if (! $account) {
            return redirect()->route('schedule')->withInput()->with('error', self::NOT_SCHEDULABLE);
        }

        $shift = [
            'staffId' => $account['uid'],
            'staff' => $account['name'],
            'role' => $account['role'],
            'day' => $input['day'],
            'shift' => $input['shift'],
            'room' => $input['room'],
        ];

        if ($this->shifts->hasConflict($shift)) {
            return redirect()->route('schedule')->withInput()->with('error', 'Schedule conflict detected: this staff member already has a shift at that time, or the room is already assigned to another staff member.');
        }

        $this->schedule->addShift($shift);

        return redirect()->route('schedule')->with('success', 'Staff schedule added successfully.');
    }

    public function storeTimeOff(Request $request): RedirectResponse
    {
        $input = StaffScheduleValidation::timeOff($request);

        if ($refused = $this->refuseOthersSchedule($request, $input['staff_id'], 'time_off')) {
            return $refused;
        }

        $account = $this->schedule->schedulableAccount($input['staff_id']);
        if (! $account) {
            return redirect()->route('schedule')->withInput()->with('error', self::NOT_SCHEDULABLE);
        }

        $this->schedule->addTimeOff($input + ['staffId' => $account['uid'], 'staff' => $account['name']]);

        return redirect()->route('schedule')->with('success', 'Time off entry added successfully.');
    }

    /**
     * A therapist may only schedule themselves; administrators schedule anyone.
     * Checked on the server because the form's dropdown alone doesn't stop a
     * crafted request. Returns the error redirect, or null when allowed.
     */
    private function refuseOthersSchedule(Request $request, string $staffId, string $kind): ?RedirectResponse
    {
        /** @var StaffUser $user */
        $user = $request->user();
        if (! $user->isTherapist() || $staffId === $user->id) {
            return null;
        }

        Log::warning('schedule.others_refused', ['by' => $user->id, 'target' => $staffId, 'kind' => $kind]);

        return redirect()->route('schedule')->withInput()->with('error', self::ONLY_OWN);
    }

    /** Who the add-shift / add-time-off forms offer: everyone for admins, only themselves for a therapist. */
    private function formStaff(StaffUser $user, array $staffDirectory): array
    {
        if (! $user->isTherapist()) {
            return $staffDirectory;
        }

        return array_values(array_filter($staffDirectory, fn (array $staff) => $staff['uid'] === $user->id));
    }
}
