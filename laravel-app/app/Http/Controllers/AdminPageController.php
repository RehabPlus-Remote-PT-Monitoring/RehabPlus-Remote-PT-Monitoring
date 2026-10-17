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

    public function billing(): View
    {
        return view('admin.billing', [
            'sessionFees' => '₱0.00',
            'paymentStatus' => '0',
            'outstanding' => '₱0.00',
            'paymentHistory' => 0,
            'payments' => [],
        ]);
    }

    public function inventory(): View
    {
        $items = \App\Models\InventoryItem::orderBy('item')->get();

        return view('admin.inventory', [
            'totalStock' => $items->sum('stock'),
            'lowStock' => $items->whereIn('status', ['Low', 'Critical'])->count(),
            'restockNeeded' => $items->filter(fn ($item) => $item->stock <= $item->reorder)->count(),
            'items' => $items,
        ]);
    }
}
