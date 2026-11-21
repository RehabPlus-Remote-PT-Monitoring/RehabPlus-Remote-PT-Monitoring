{{-- Phone number with a country code. Needs $field (input name), $label, $country (ISO code), $number, $initial (null for new records) and $required. --}}
@php($countries = \App\Helpers\PhoneNumber::countries())
@php($selected = collect($countries)->firstWhere('iso', $country) ?? collect($countries)->firstWhere('iso', \App\Helpers\PhoneNumber::DEFAULT_COUNTRY))
<div class="col-md-6" data-phone-group>
    <label for="{{ $field }}" class="form-label small fw-semibold">{{ $label }}</label>
    <div class="phone-field">
        {{-- The closed picker shows the short and dial codes; the invisible select on top still lists the full country names. --}}
        <div class="form-select phone-country">
            <span data-phone-code>{{ $selected['iso'] }} +{{ $selected['dial'] }}</span>
            <select name="{{ $field }}_country" data-phone-country aria-label="Country code">
                @foreach ($countries as $c)
                    <option value="{{ $c['iso'] }}" data-dial="{{ $c['dial'] }}" data-min="{{ $c['min'] }}" data-max="{{ $c['max'] }}" data-digits="{{ $c['digits'] }}" data-example="{{ $c['example'] }}" data-pattern="{{ $c['pattern'] }}" @selected($selected['iso'] === $c['iso'])>{{ $c['name'] }} (+{{ $c['dial'] }})</option>
                @endforeach
            </select>
        </div>
        <div class="form-control phone-box @error($field) is-invalid @enderror" data-phone-box>
            <input id="{{ $field }}" type="text" name="{{ $field }}" class="form-control phone-input" inputmode="numeric" data-digits-only data-phone-number placeholder="{{ $selected['example'] }}" maxlength="{{ $selected['max'] }}" @if ($initial !== null) data-initial="{{ $initial }}" @endif value="{{ $number }}" @required($required)>
        </div>
    </div>
    <div class="small text-danger mt-1" role="alert" data-phone-error @unless ($errors->has($field)) hidden @endunless>{{ $errors->first($field) }}</div>
    <div class="form-text" data-phone-hint @if ($errors->has($field)) hidden @endif>Enter {{ $selected['digits'] }} without the country code.</div>
</div>
