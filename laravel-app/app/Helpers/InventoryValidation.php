<?php

namespace App\Helpers;

use App\Services\Inventory\InventoryService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class InventoryValidation
{
    public static function item(Request $request): array
    {
        return $request->validate([
            'item' => ['required', 'string', 'max:150'],
            'category' => ['required', 'string', 'max:100'],
            'stock' => ['required', 'integer', 'min:0'],
            'reorder' => ['nullable', 'integer', 'min:0'],
            'status' => ['required', Rule::in(InventoryService::STATUSES)],
        ]);
    }

    public static function status(Request $request): array
    {
        return $request->validate([
            'status' => ['required', Rule::in(InventoryService::STATUSES)],
        ]);
    }
}
