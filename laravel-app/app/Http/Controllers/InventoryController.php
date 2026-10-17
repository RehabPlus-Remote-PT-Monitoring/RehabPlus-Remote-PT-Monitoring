<?php

namespace App\Http\Controllers;

use App\Helpers\InventoryValidation;
use App\Models\InventoryItem;
use App\Services\Inventory\InventoryService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;

class InventoryController extends Controller
{
    public function __construct(private InventoryService $inventory)
    {
    }

    public function index(): View
    {
        return view('admin.inventory', $this->inventory->overview());
    }

    public function create(): View
    {
        return view('admin.inventory', $this->inventory->overview());
    }

    public function store(Request $request): RedirectResponse
    {
        InventoryItem::create(InventoryValidation::item($request));

        return redirect()->route('inventory.index')->with('success', 'Inventory item added successfully.');
    }

    public function edit(InventoryItem $inventory): View
    {
        return view('admin.inventory', $this->inventory->overview($inventory));
    }

    public function update(Request $request, InventoryItem $inventory): RedirectResponse
    {
        $inventory->update(InventoryValidation::item($request));

        return redirect()->route('inventory.index')->with('success', 'Inventory item updated successfully.');
    }

    public function updateStatus(Request $request, InventoryItem $inventory): RedirectResponse
    {
        $inventory->update(InventoryValidation::status($request));

        return redirect()->route('inventory.index')->with('success', 'Inventory status updated successfully.');
    }

    public function destroy(InventoryItem $inventory): RedirectResponse
    {
        $inventory->delete();

        return redirect()->route('inventory.index')->with('success', 'Inventory item deleted successfully.');
    }
}
