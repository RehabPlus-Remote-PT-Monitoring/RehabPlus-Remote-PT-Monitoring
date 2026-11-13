<?php

namespace Tests\Unit;

use App\Rules\OfficialEmailDomain;
use Tests\TestCase;

class OfficialEmailDomainTest extends TestCase
{
    public function test_accepts_addresses_ending_in_the_clinic_domain(): void
    {
        foreach (['ada@rehabplus.com', 'Ada.Lee@RehabPlus.com', '  ada@rehabplus.com  '] as $email) {
            $this->assertTrue(OfficialEmailDomain::allows($email), $email);
        }
    }

    public function test_rejects_other_domains_and_lookalikes(): void
    {
        foreach ([
            'ada@gmail.com', 'ada@yahoo.com', 'ada@rehabplus.com.evil.net', 'ada@sub.rehabplus.com',
            'ada@notrehabplus.com', 'ada@rehabplus.co', '@rehabplus.com', 'a b@rehabplus.com', 'ada',
        ] as $email) {
            $this->assertFalse(OfficialEmailDomain::allows($email), $email);
        }
    }
}
