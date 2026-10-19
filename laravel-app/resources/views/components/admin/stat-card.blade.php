@props(['label', 'value', 'icon', 'tone'])

<div class="col-md-4">
    <div class="card stat-card">
        <div class="d-flex justify-content-between align-items-center gap-3">
            <div>
                <div class="stat-label mb-2">{{ $label }}</div>
                <div class="display-5 text-{{ $tone }}">{{ $value }}</div>
            </div>
            <span class="stat-icon text-{{ $tone }}">
                <i class="bi {{ $icon }}"></i>
            </span>
        </div>
    </div>
</div>