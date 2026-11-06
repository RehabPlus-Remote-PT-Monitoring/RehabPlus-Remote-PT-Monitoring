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

    public function test_a_leading_zero_is_refused_because_a_text_could_never_reach_that_number(): void
    {
        $this->assertSame('Leave out the 0 at the start of the phone number.', PhoneNumber::problem('PH', '0917555010'));
    }

    public function test_stored_numbers_become_numbers_a_text_can_be_sent_to(): void
    {
        $this->assertSame('+639175550101', PhoneNumber::toE164('+639175550101'));
        $this->assertSame('+639175550101', PhoneNumber::toE164('0917 555 0101'));
        $this->assertSame('+639175550101', PhoneNumber::toE164('+6309175550101'));
        $this->assertSame('', PhoneNumber::toE164(''));
        $this->assertNull(PhoneNumber::toE164('12345'));
    }

    public function test_a_random_number_of_the_right_length_is_invalid(): void
    {
        foreach (['1234567890', '5551234567', '9999999999', '9876543210'] as $random) {
            $this->assertSame(PhoneNumber::FORMAT_MESSAGE, PhoneNumber::problem('PH', $random), $random);
        }

        $this->assertNull(PhoneNumber::problem('PH', '8131234567'));
        $this->assertNull(PhoneNumber::problem('PH', '8951234567'));
        $this->assertSame(PhoneNumber::FORMAT_MESSAGE, PhoneNumber::problem('US', '1025550123'));
    }

    public function test_every_country_accepts_its_own_example_number(): void
    {
        foreach (PhoneNumber::countries() as $country) {
            $this->assertNull(PhoneNumber::problem($country['iso'], $country['example']), $country['iso']);
        }
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
