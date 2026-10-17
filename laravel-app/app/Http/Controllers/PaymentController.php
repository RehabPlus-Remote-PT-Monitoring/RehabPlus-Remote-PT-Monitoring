<?php

namespace App\Http\Controllers;

use App\Helpers\PaymentValidation;
use App\Models\PaymentRecord;
use App\Services\Payment\PaymentService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class PaymentController extends Controller
{
    public function index(PaymentService $payments): View
    {
        return view('admin.billing', $payments->overview());
    }

    public function store(Request $request): RedirectResponse
    {
        PaymentRecord::create(PaymentValidation::payment($request));

        return redirect()->route('billing')->with('success', 'Payment record added successfully.');
    }

    public function updateStatus(Request $request, int $id): RedirectResponse
    {
        PaymentRecord::findOrFail($id)->update(PaymentValidation::status($request));

        return redirect()->route('billing')->with('success', 'Payment status updated successfully.');
    }

    public function delete(int $id): RedirectResponse
    {
        PaymentRecord::findOrFail($id)->delete();

        return redirect()->route('billing')->with('success', 'Payment record deleted successfully.');
    }
}
