<?php

namespace App\Helpers;

use App\Services\Clinic\ClinicRecord;
use App\Services\Inventory\InventoryService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class InventoryValidation
{
    /** Whole numbers up to the clinic's limit, plus an item's saved number if it's above that. */
    public static function quantityChoices(mixed $current = null): array
    {
        return collect(range(0, config('clinic.inventory_max_quantity')))
            ->when($current !== null, fn ($choices) => $choices->push((int) $current))
            ->unique()
            ->sort()
            ->values()
            ->all();
    }

    /** $current is the item being edited, whose saved numbers stay valid. */
    public static function item(Request $request, ?ClinicRecord $current = null): array
    {
        return $request->validate([
            'item' => ['required', 'string', 'max:150'],
            'category' => ['required', 'string', 'max:100'],
            'stock' => ['required', Rule::in(self::quantityChoices($current?->stock))],
            'reorder' => ['nullable', Rule::in(self::quantityChoices($current?->reorder))],
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
