<?php

namespace Tests\Unit;

use App\Services\Patient\ClinicalProfileService;
use Carbon\CarbonImmutable;
use PHPUnit\Framework\TestCase;

/** The tolerance review flag (computed on the patient page, never stored). */
class ToleranceReviewTest extends TestCase
{
    private CarbonImmutable $now;

    protected function setUp(): void
    {
        parent::setUp();
        $this->now = CarbonImmutable::parse('2026-11-15 12:00:00', 'UTC');
    }

    private function session(string $id, ?int $pain, bool $endedEarly = false, int $daysAgo = 1): array
    {
        return ['id' => $id, 'painLevel' => $pain, 'endedEarly' => $endedEarly, 'startTime' => $this->now->subDays($daysAgo)];
    }

    private function flagged(array $profile, array $sessions): array
    {
        return array_column(ClinicalProfileService::toleranceReview(ClinicalProfileService::present($profile), $sessions, $this->now), 'id');
    }

    public function test_low_tolerance_flags_pain_six_and_ended_early(): void
    {
        $sessions = [$this->session('pain5', 5), $this->session('pain6', 6, daysAgo: 3), $this->session('early', 0, true, daysAgo: 2)];

        $this->assertSame(['early', 'pain6'], $this->flagged(['lowTolerance' => true], $sessions), 'newest first');
    }

    public function test_any_nutrition_flag_makes_the_patient_sensitive(): void
    {
        $this->assertSame(['pain6'], $this->flagged(['nutritionFlags' => ['anemia']], [$this->session('pain6', 6)]));
    }

    public function test_without_flags_only_pain_eight_or_more(): void
    {
        $sessions = [$this->session('pain7', 7), $this->session('early', 1, true), $this->session('pain8', 8)];

        $this->assertSame(['pain8'], $this->flagged([], $sessions));
        $this->assertSame(['pain8'], $this->flagged(['nutritionFlags' => ['not_a_code']], $sessions), 'unknown codes are ignored');
    }

    public function test_only_the_last_fourteen_days_count(): void
    {
        $sessions = [$this->session('old', 10, daysAgo: 15), $this->session('edge', 9, daysAgo: 13), ['id' => 'noTime', 'painLevel' => 10, 'endedEarly' => true, 'startTime' => null]];

        $this->assertSame(['edge'], $this->flagged(['lowTolerance' => true], $sessions));
    }
}
