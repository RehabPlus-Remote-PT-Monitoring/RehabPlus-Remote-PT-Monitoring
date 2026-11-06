{{-- Phone number with a country code. Needs $field (input name), $label, $country (ISO code), $number, $initial (null for new records) and $required. --}}
@php($countries = \App\Helpers\PhoneNumber::countries())
@php($selected = collect($countries)->firstWhere('iso', $country) ?? $countries[0])
<div class="col-md-6" data-phone-group>
    <label for="{{ $field }}" class="form-label small fw-semibold">{{ $label }}</label>
    <div class="phone-field">
        {{-- The closed picker shows just the short code; the invisible select on top still lists the full country names. --}}
        <div class="form-select phone-country">
            <span data-phone-iso>{{ $selected['iso'] }}</span>
            <select name="{{ $field }}_country" data-phone-country aria-label="Country code">
                @foreach ($countries as $c)
                    <option value="{{ $c['iso'] }}" data-dial="{{ $c['dial'] }}" data-min="{{ $c['min'] }}" data-max="{{ $c['max'] }}" data-digits="{{ $c['digits'] }}" data-example="{{ $c['example'] }}" data-pattern="{{ $c['pattern'] }}" @selected($selected['iso'] === $c['iso'])>+{{ $c['dial'] }} {{ $c['name'] }}</option>
                @endforeach
            </select>
        </div>
        {{-- The dial code only looks like part of the number: the input still holds just the national digits. --}}
        <div class="form-control phone-box @error($field) is-invalid @enderror" data-phone-box>
            <span class="phone-dial" data-phone-dial>+{{ $selected['dial'] }}</span>
            <input id="{{ $field }}" type="text" name="{{ $field }}" class="form-control phone-input" inputmode="numeric" data-digits-only data-phone-number placeholder="{{ $selected['example'] }}" maxlength="{{ $selected['max'] }}" @if ($initial !== null) data-initial="{{ $initial }}" @endif value="{{ $number }}" @required($required)>
        </div>
    </div>
    <div class="small text-danger mt-1" role="alert" data-phone-error @unless ($errors->has($field)) hidden @endunless>{{ $errors->first($field) }}</div>
    <div class="form-text" data-phone-hint @if ($errors->has($field)) hidden @endif>Enter {{ $selected['digits'] }} without the country code.</div>
</div>
