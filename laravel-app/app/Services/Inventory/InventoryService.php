<?php

namespace App\Services\Inventory;

use App\Models\InventoryItem;

class InventoryService
{
    public function overview(?InventoryItem $editing = null): array
    {
        $items = InventoryItem::orderBy('item')->get();

        return [
            'totalStock' => $items->sum('stock'),
            'lowStock' => $items->whereIn('status', ['Low', 'Critical'])->count(),
            'restockNeeded' => $items->filter(fn (InventoryItem $item) => $item->stock <= $item->reorder)->count(),
            'items' => $items,
            'inventoryItem' => $editing,
        ];
    }
}
