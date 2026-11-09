<?php

namespace Tests\Unit;

use App\Rules\StaffEmailDomain;
use PHPUnit\Framework\TestCase;

class StaffEmailDomainTest extends TestCase
{
    public function test_accepts_the_clinic_domain_and_gmail(): void
    {
        foreach (['ada@rehabplus.com', 'Ada.Lee@RehabPlus.com', 'ada.lee16@gmail.com', '  Ada@Gmail.com  '] as $email) {
            $this->assertTrue(StaffEmailDomain::allows($email), $email);
        }
    }

    public function test_rejects_other_domains_and_lookalikes(): void
    {
        foreach ([
            'ada@yahoo.com', 'ada@googlemail.com', 'ada@gmail.com.evil.net', 'ada@notgmail.com', 'ada@sub.gmail.com',
            'ada@rehabplus.com.evil.net', 'ada@gmail.co', '@gmail.com', 'a b@gmail.com', 'ada',
        ] as $email) {
            $this->assertFalse(StaffEmailDomain::allows($email), $email);
        }
    }
}
