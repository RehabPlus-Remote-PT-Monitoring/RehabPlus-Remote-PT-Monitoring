<?php

namespace App\Services\Payment;

use App\Models\PaymentRecord;

class PaymentService
{
    public function overview(): array
    {
        $payments = PaymentRecord::orderByDesc('date')->get();

        return [
            'sessionFees' => '₱' . number_format($payments->sum('fee'), 2),
            'paymentStatus' => $payments->where('status', 'Paid')->count(),
            'outstanding' => '₱' . number_format($payments->whereIn('status', ['Pending', 'Partial'])->sum('fee'), 2),
            'paymentHistory' => $payments->count(),
            'payments' => $payments,
        ];
    }
}
