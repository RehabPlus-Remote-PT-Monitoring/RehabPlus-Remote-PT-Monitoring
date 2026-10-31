{{-- Phone number with a country code. Needs $field (input name), $label, $country (ISO code), $number, $initial (null for new records) and $required. --}}
@php($countries = \App\Helpers\PhoneNumber::countries())
@php($selected = collect($countries)->firstWhere('iso', $country) ?? $countries[0])
<div class="col-md-6">
    <label for="{{ $field }}" class="form-label small fw-semibold">{{ $label }}</label>
    <div class="input-group" data-phone-field>
        <select name="{{ $field }}_country" class="form-select flex-grow-0" style="max-width: 11rem;" data-phone-country aria-label="Country code">
            @foreach ($countries as $c)
                <option value="{{ $c['iso'] }}" data-dial="{{ $c['dial'] }}" data-min="{{ $c['min'] }}" data-max="{{ $c['max'] }}" data-digits="{{ $c['digits'] }}" data-example="{{ $c['example'] }}" @selected($country === $c['iso'])>{{ $c['name'] }} (+{{ $c['dial'] }})</option>
            @endforeach
        </select>
        <input id="{{ $field }}" type="text" name="{{ $field }}" class="form-control @error($field) is-invalid @enderror" inputmode="numeric" data-digits-only data-phone-number placeholder="{{ $selected['example'] }}" maxlength="{{ $selected['max'] }}" @if ($initial !== null) data-initial="{{ $initial }}" @endif value="{{ $number }}" @required($required)>
        @error($field)
            <div class="invalid-feedback">{{ $message }}</div>
        @enderror
    </div>
    <div class="form-text" data-phone-hint>Enter {{ $selected['digits'] }} without the country code.</div>
</div>
