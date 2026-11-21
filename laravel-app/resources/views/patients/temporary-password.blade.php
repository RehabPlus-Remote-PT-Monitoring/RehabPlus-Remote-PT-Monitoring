{{-- A new or reset app password, shown once. Not an alert: it has to stay until it has been passed on. Needs $patient. --}}
@if (session('temporary_password'))
    @php
        $password = session('temporary_password');
        $phoneNumber = str_replace(' ', '', \App\Helpers\PhoneNumber::display($patient['phone']));
        $text = "Hi {$patient['name']}, your new RehabPlus app password is {$password}. Sign in with {$patient['email']}.";
    @endphp
    <div class="card shadow-sm border-0 mb-4" role="status" data-temporary-password>
        <div class="card-body">
            <p class="fw-semibold mb-1"><i class="bi bi-key me-1"></i>Temporary password for {{ $patient['name'] }}</p>
            <p class="text-muted small mb-3">Call or text this to the patient. It is shown only now, so pass it on before leaving this page.</p>
            <div class="d-flex flex-wrap align-items-center gap-2 mb-2">
                <code class="fs-5 user-select-all" data-copy-source>{{ $password }}</code>
                <button type="button" class="btn btn-sm btn-outline-primary" data-copy-password><i class="bi bi-clipboard me-1"></i>Copy</button>
                @if ($phoneNumber !== '')
                    <a class="btn btn-sm btn-outline-primary" href="tel:{{ $phoneNumber }}"><i class="bi bi-telephone me-1"></i>Call {{ \App\Helpers\PhoneNumber::display($patient['phone']) }}</a>
                    <a class="btn btn-sm btn-outline-primary" href="sms:{{ $phoneNumber }}?body={{ rawurlencode($text) }}"><i class="bi bi-chat-text me-1"></i>Text</a>
                @endif
            </div>
            <p class="text-muted small mb-0">
                Sign-in email: {{ $patient['email'] ?: '—' }}
                @if ($phoneNumber === '')
                    <span class="d-block text-danger mt-1">No phone number on file for this patient. Add one with Edit.</span>
                @endif
            </p>
        </div>
    </div>
@endif
