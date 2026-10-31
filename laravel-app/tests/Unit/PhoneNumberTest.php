<?php

namespace Tests\Unit;

use App\Helpers\PhoneNumber;
use Tests\TestCase;

class PhoneNumberTest extends TestCase
{
    public function test_a_philippine_mobile_number_has_ten_digits_after_the_country_code(): void
    {
        $this->assertNull(PhoneNumber::problem('PH', '9175550101'));
        $this->assertSame('Enter exactly 10 digits for the phone number in Philippines.', PhoneNumber::problem('PH', '917555010'));
        $this->assertSame('Enter exactly 10 digits for the phone number in Philippines.', PhoneNumber::problem('PH', '09175550101'));
        $this->assertSame('Phone number can only contain numbers.', PhoneNumber::problem('PH', '917555abcd'));
    }

    public function test_each_country_has_its_own_length_range(): void
    {
        $this->assertNull(PhoneNumber::problem('NZ', '21234567'));
        $this->assertNull(PhoneNumber::problem('NZ', '2123456789'));
        $this->assertSame('Enter 8 to 10 digits for the phone number in New Zealand.', PhoneNumber::problem('NZ', '2123456'));
        $this->assertSame('Enter exactly 9 digits for the phone number in Australia.', PhoneNumber::problem('AU', '4123456789'));
    }

    public function test_numbers_are_stored_with_the_country_code(): void
    {
        $this->assertSame('+639175550101', PhoneNumber::toStored('PH', '9175550101'));
        $this->assertSame('+12025550123', PhoneNumber::toStored('US', '2025550123'));
    }

    public function test_a_stored_number_is_split_back_into_country_and_national_digits(): void
    {
        $this->assertSame(['iso' => 'PH', 'national' => '9175550101'], PhoneNumber::parse('+639175550101'));
        $this->assertSame(['iso' => 'GB', 'national' => '7400123456'], PhoneNumber::parse('+447400123456'));
        // Numbers saved before country codes existed were Philippine numbers with a leading 0.
        $this->assertSame(['iso' => 'PH', 'national' => '9175550101'], PhoneNumber::parse('0917 555 0101'));
        $this->assertSame(['iso' => 'PH', 'national' => ''], PhoneNumber::parse(null));
    }
}
