<?php

namespace App\Services\Inventory;

use App\Services\Clinic\ClinicRecord;
use App\Services\Clinic\ClinicStore;

/** Inventory and supplies (Firestore `inventory`, see ClinicStore). */
class InventoryService
{
    /** Stock statuses: the Status list on the form and the Actions list on each item both use these. */
    public const STATUSES = ['In Stock', 'Low Stock', 'Out of Stock'];

    /** Items saved before the statuses were renamed from the health words. */
    private const LEGACY_STATUSES = ['Healthy' => 'In Stock', 'Low' => 'Low Stock', 'Critical' => 'Out of Stock'];

    public function __construct(private ClinicStore $store)
    {
    }

    public function overview(?ClinicRecord $editing = null): array
    {
        $items = $this->store->all(ClinicStore::INVENTORY)
            ->map(fn (ClinicRecord $item) => $this->withCurrentStatus($item))
            ->sortBy(fn (ClinicRecord $item) => strtolower((string) $item->item))
            ->values();

        return [
            'totalStock' => $items->sum(fn (ClinicRecord $item) => (int) $item->stock),
            'lowStock' => $items->whereIn('status', ['Low Stock', 'Out of Stock'])->count(),
            'restockNeeded' => $items->filter(fn (ClinicRecord $item) => (int) $item->stock <= (int) $item->reorder)->count(),
            'statuses' => self::STATUSES,
            'items' => $items,
            'inventoryItem' => $editing,
        ];
    }

    public function find(string $id): ClinicRecord
    {
        return $this->store->findOrFail(ClinicStore::INVENTORY, $id);
    }

    public function create(array $data): string
    {
        return $this->store->create(ClinicStore::INVENTORY, $this->fields($data));
    }

    public function update(ClinicRecord $item, array $data): void
    {
        $this->store->update(ClinicStore::INVENTORY, $item->id, $this->fields($data));
    }

    public function updateStatus(ClinicRecord $item, string $status): void
    {
        $this->store->update(ClinicStore::INVENTORY, $item->id, ['status' => $status]);
    }

    public function delete(ClinicRecord $item): void
    {
        $this->store->delete(ClinicStore::INVENTORY, $item->id);
    }

    /** The item with its status in the current wording (older health words are mapped; nothing is rewritten). */
    private function withCurrentStatus(ClinicRecord $item): ClinicRecord
    {
        if (! isset(self::LEGACY_STATUSES[$item->status])) {
            return $item;
        }

        return new ClinicRecord(array_merge($item->toArray(), ['status' => self::LEGACY_STATUSES[$item->status]]));
    }

    private function fields(array $data): array
    {
        return [
            'item' => $data['item'],
            'category' => $data['category'],
            'stock' => (int) $data['stock'],
            'reorder' => isset($data['reorder']) ? (int) $data['reorder'] : null,
            'status' => $data['status'],
        ];
    }
}
