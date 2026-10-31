<?php

namespace Tests\Feature;

use App\Mail\PasswordResetCode;
use App\Services\Auth\PasswordResetService;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\Mail;
use Tests\Support\FakeFirebase;
use Tests\TestCase;

/** Forgot password: emailed 6-digit code, then a new Firebase password. */
class PasswordResetTest extends TestCase
{
    use FakeFirebase;

    private const SENT = 'If an account exists for that email';

    protected function setUp(): void
    {
        parent::setUp();
        Mail::fake();
    }

    public function test_login_links_to_the_forgot_password_page(): void
    {
        $this->get('/login')->assertSee(route('password.request'), false);
        $this->get('/forgot-password')->assertOk()->assertSee('Send Code');
    }

    public function test_staff_get_a_code_by_email_and_can_set_a_new_password(): void
    {
        $this->staff('therapist', 'thUid', 'Dr. Reyes', 'reyes@clinic.com');

        $this->post('/forgot-password', ['email' => 'Reyes@Clinic.com'])
            ->assertRedirect('/forgot-password/verify')
            ->assertSessionHas('success', fn ($m) => str_contains($m, self::SENT));

        $code = $this->sentCode('reyes@clinic.com');
        $this->assertMatchesRegularExpression('/^\d{6}$/', $code);

        // Only a keyed hash of the code is stored, never the code itself.
        $doc = $this->resetDoc('reyes@clinic.com');
        $this->assertSame('thUid', $doc['uid']);
        $this->assertNotSame($code, $doc['codeHash']);
        $this->assertStringNotContainsString($code, json_encode($doc));

        $this->post('/forgot-password/verify', ['code' => $code])->assertRedirect('/reset-password');
        $this->get('/reset-password')->assertOk()->assertSee('Change Password');

        $this->post('/reset-password', ['password' => 'brand-new-pass', 'password_confirmation' => 'brand-new-pass'])
            ->assertRedirect('/login')
            ->assertSessionHas('success');

        $this->assertSame('brand-new-pass', $this->authUsers['reyes@clinic.com']['password']);
        $this->assertNull($this->resetDoc('reyes@clinic.com'));

        $this->post('/login', ['email' => 'reyes@clinic.com', 'password' => 'brand-new-pass'])->assertRedirect('/dashboard');
    }

    public function test_unknown_and_patient_emails_get_the_same_answer_and_no_email(): void
    {
        $this->patientDoc('pat1');

        foreach (['nobody@clinic.com', 'pat1@mail.com'] as $email) {
            $this->flushSession();
            $this->post('/forgot-password', ['email' => $email])
                ->assertRedirect('/forgot-password/verify')
                ->assertSessionHas('success', fn ($m) => str_contains($m, self::SENT));
            $this->assertNull($this->resetDoc($email));
        }

        Mail::assertNothingSent();

        $this->post('/forgot-password/verify', ['code' => '123456'])
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'incorrect or has expired'));
    }

    public function test_inactive_staff_get_no_email(): void
    {
        $this->staff('staff', 'deskUid', 'Desk', 'desk@clinic.com');
        $this->docs['users/deskUid']['active'] = false;

        $this->post('/forgot-password', ['email' => 'desk@clinic.com'])->assertSessionHas('success');

        Mail::assertNothingSent();
    }

    public function test_a_code_is_cancelled_after_too_many_wrong_tries(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $code = $this->sentCode('admin@clinic.com');
        $wrong = $code === '000000' ? '111111' : '000000';

        for ($i = 0; $i < PasswordResetService::MAX_ATTEMPTS; $i++) {
            $this->post('/forgot-password/verify', ['code' => $wrong])->assertSessionHas('error');
        }

        // Even the right code no longer works.
        $this->post('/forgot-password/verify', ['code' => $code])->assertSessionHas('error');
        $this->get('/reset-password')->assertRedirect('/forgot-password');
        $this->assertSame('secret-pass', $this->authUsers['admin@clinic.com']['password']);
    }

    public function test_parallel_wrong_guesses_cannot_share_one_attempt_count(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $code = $this->sentCode('admin@clinic.com');
        $wrong = $code === '000000' ? '111111' : '000000';
        $path = 'passwordResets/'.hash('sha256', 'admin@clinic.com');

        // Another guess (in a parallel request) is saved after this one read the
        // doc: this one must not overwrite that count with its stale "1".
        $this->beforeNextCommit = function () use ($path) {
            $this->docs[$path]['attempts'] = 4;
        };
        $this->post('/forgot-password/verify', ['code' => $wrong])->assertSessionHas('error');
        $this->assertSame(4, $this->resetDoc('admin@clinic.com')['attempts']);

        // The next guess is the 5th and last: the code is dropped.
        $this->post('/forgot-password/verify', ['code' => $wrong])->assertSessionHas('error');
        $this->assertNull($this->resetDoc('admin@clinic.com')['codeHash']);
        $this->post('/forgot-password/verify', ['code' => $code])->assertSessionHas('error');
        $this->get('/reset-password')->assertRedirect('/forgot-password');
    }

    public function test_a_right_code_loses_to_a_parallel_lockout(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $code = $this->sentCode('admin@clinic.com');
        $path = 'passwordResets/'.hash('sha256', 'admin@clinic.com');

        // A parallel wrong guess used up the last try between this request's read and write.
        $this->beforeNextCommit = function () use ($path) {
            $this->docs[$path] = ['codeHash' => null, 'codeExpiresAt' => null, 'attempts' => 5] + $this->docs[$path];
        };
        $this->post('/forgot-password/verify', ['code' => $code])->assertSessionHas('error');
        $this->get('/reset-password')->assertRedirect('/forgot-password');
        $this->assertNull($this->resetDoc('admin@clinic.com')['tokenHash'] ?? null);
    }

    public function test_code_checks_are_conditional_writes(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $this->post('/forgot-password/verify', ['code' => $this->sentCode('admin@clinic.com')]);

        $write = end($this->commits)[0];
        $this->assertArrayHasKey('updateTime', $write['currentDocument']);
    }

    public function test_codes_expire(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $code = $this->sentCode('admin@clinic.com');

        $this->travel(PasswordResetService::CODE_MINUTES + 1)->minutes();

        $this->post('/forgot-password/verify', ['code' => $code])->assertSessionHas('error');
    }

    public function test_resend_waits_for_the_cooldown(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);

        // The button starts disabled with the seconds left, for the page's countdown.
        $this->get('/forgot-password/verify')
            ->assertSee('id="resendButton"', false)
            ->assertSee('data-resend-in="'.PasswordResetService::RESEND_SECONDS.'"', false)
            ->assertSee('disabled', false);

        $this->post('/forgot-password/resend')->assertSessionHas('error', fn ($m) => str_contains($m, 'Wait'));
        Mail::assertSentCount(1);

        $this->travel(PasswordResetService::RESEND_SECONDS + 1)->seconds();
        $this->post('/forgot-password/resend')->assertSessionHas('success');
        Mail::assertSentCount(2);

        // A new code replaces the old one.
        $codes = Mail::sent(PasswordResetCode::class)->map(fn ($m) => $m->code)->all();
        if ($codes[0] !== $codes[1]) {
            $this->post('/forgot-password/verify', ['code' => $codes[0]])->assertSessionHas('error');
        }
        $this->post('/forgot-password/verify', ['code' => $codes[1]])->assertRedirect('/reset-password');
    }

    public function test_the_cooldown_holds_even_if_the_browser_session_is_cleared(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);

        $this->flushSession();
        $this->post('/forgot-password', ['email' => 'admin@clinic.com'])
            ->assertSessionHas('success', fn ($m) => str_contains($m, self::SENT));

        Mail::assertSentCount(1);
    }

    public function test_codes_per_email_are_capped_per_hour(): void
    {
        $this->withoutMiddleware(ThrottleRequests::class);
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');

        for ($i = 0; $i < PasswordResetService::MAX_SENDS_PER_HOUR + 2; $i++) {
            $this->flushSession();
            $this->post('/forgot-password', ['email' => 'admin@clinic.com'])->assertSessionHas('success');
            $this->travel(PasswordResetService::RESEND_SECONDS + 1)->seconds();
        }

        Mail::assertSentCount(PasswordResetService::MAX_SENDS_PER_HOUR);
    }

    public function test_requests_per_ip_are_capped_per_hour(): void
    {
        $this->withoutMiddleware(ThrottleRequests::class);

        for ($i = 0; $i < PasswordResetService::MAX_IP_REQUESTS_PER_HOUR; $i++) {
            $this->post('/forgot-password', ['email' => "user{$i}@clinic.com"])->assertSessionHas('success');
        }

        $this->post('/forgot-password', ['email' => 'one-more@clinic.com'])
            ->assertSessionHas('error', fn ($m) => str_contains($m, 'Too many'));
    }

    public function test_steps_cannot_be_skipped(): void
    {
        $this->get('/forgot-password/verify')->assertRedirect('/forgot-password');
        $this->get('/reset-password')->assertRedirect('/forgot-password');
        $this->post('/reset-password', ['password' => 'brand-new-pass', 'password_confirmation' => 'brand-new-pass'])
            ->assertRedirect('/forgot-password');

        // A token that isn't the one stored in Firestore is refused.
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $this->withSession(['password_reset.token' => 'forged-token'])
            ->post('/reset-password', ['password' => 'brand-new-pass', 'password_confirmation' => 'brand-new-pass'])
            ->assertRedirect('/forgot-password');
        $this->assertSame('secret-pass', $this->authUsers['admin@clinic.com']['password']);
    }

    public function test_the_new_password_must_be_confirmed_and_long_enough(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $this->post('/forgot-password/verify', ['code' => $this->sentCode('admin@clinic.com')]);

        $this->post('/reset-password', ['password' => 'short', 'password_confirmation' => 'short'])->assertSessionHasErrors('password');
        $this->post('/reset-password', ['password' => 'long-enough-1', 'password_confirmation' => 'different-1'])->assertSessionHasErrors('password');
        $this->assertSame('secret-pass', $this->authUsers['admin@clinic.com']['password']);
    }

    public function test_reset_tokens_expire(): void
    {
        $this->staff('admin', 'adUid', 'Admin', 'admin@clinic.com');
        $this->post('/forgot-password', ['email' => 'admin@clinic.com']);
        $this->post('/forgot-password/verify', ['code' => $this->sentCode('admin@clinic.com')]);

        $this->travel(PasswordResetService::TOKEN_MINUTES + 1)->minutes();

        $this->post('/reset-password', ['password' => 'brand-new-pass', 'password_confirmation' => 'brand-new-pass'])
            ->assertRedirect('/forgot-password');
        $this->assertSame('secret-pass', $this->authUsers['admin@clinic.com']['password']);
    }

    private function sentCode(string $email): string
    {
        $mail = Mail::sent(PasswordResetCode::class, fn ($m) => $m->hasTo($email))->last();
        $this->assertNotNull($mail, "No reset code was emailed to {$email}.");

        return $mail->code;
    }

    private function resetDoc(string $email): ?array
    {
        return $this->docs['passwordResets/'.hash('sha256', $email)] ?? null;
    }
}
