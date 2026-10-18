<?php

namespace App\Http\Controllers;

use Illuminate\View\View;

class AdminPageController extends Controller
{
    public function reports(): View
    {
        return view('admin.reports', [
            'totalRegisteredPatients' => 0,
            'activePatients' => 0,
            'newPatientsThisMonth' => 0,
            'totalAppointments' => 0,
            'completedAppointments' => 0,
            'pendingAppointments' => 0,
            'cancelledAppointments' => 0,
            'totalRevenue' => '₱0.00',
            'outstandingPayments' => '₱0.00',
            'treatmentCompletionRate' => '0%',
        ]);
    }
}
