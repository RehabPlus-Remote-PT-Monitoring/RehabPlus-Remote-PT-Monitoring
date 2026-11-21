<?php

namespace Tests\Unit;

use App\Services\Patient\ClearanceGate;
use PHPUnit\Framework\TestCase;

/**
 * The completion gate. The Flutter app re-implements the same logic
 * (lib/services/care_gate.dart) with the same cases (a)-(g): keep both
 * suites in step when a rule changes.
 */
class ClearanceGateTest extends TestCase
{
    private function rx(string $id, ?int $required, string $type = 'kneeExtension', bool $active = true): array
    {
        return ['id' => $id, 'exerciseType' => $type, 'exerciseName' => ucfirst($type), 'active' => $active, 'requiredSessions' => $required];
    }

    private function session(?string $prescriptionId, bool $endedEarly = false): array
    {
        return ['prescriptionId' => $prescriptionId, 'endedEarly' => $endedEarly];
    }

    public function test_a_no_prescriptions_is_no_program(): void
    {
        $gate = ClearanceGate::evaluate([], [$this->session('rx1')], []);

        $this->assertSame(ClearanceGate::NO_PROGRAM, $gate['state']);
        $this->assertSame([], $gate['requirements']);
        $this->assertSame([], $gate['missing']);
    }

    public function test_b_ended_early_sessions_do_not_count(): void
    {
        $gate = ClearanceGate::evaluate(
            [$this->rx('rx1', 3)],
            [$this->session('rx1'), $this->session('rx1'), $this->session('rx1', endedEarly: true)],
            [],
        );

        $this->assertSame(ClearanceGate::IN_PROGRESS, $gate['state']);
        $this->assertCount(1, $gate['missing']);
        $this->assertSame(2, $gate['missing'][0]['finished']);
        $this->assertSame(3, $gate['missing'][0]['required']);
        $this->assertSame(ClearanceGate::REASON_NOT_ENOUGH, $gate['missing'][0]['reason']);
        $this->assertSame('KneeExtension: 2/3 sessions finished', ClearanceGate::describe($gate['missing'][0]));
    }

    public function test_c_prescription_without_target_is_never_complete(): void
    {
        $gate = ClearanceGate::evaluate([$this->rx('rx1', null)], array_fill(0, 50, $this->session('rx1')), []);

        $this->assertSame(ClearanceGate::IN_PROGRESS, $gate['state']);
        $this->assertSame(ClearanceGate::REASON_NO_TARGET, $gate['missing'][0]['reason']);
        $this->assertSame(50, $gate['missing'][0]['finished']);
        $this->assertNull($gate['missing'][0]['required']);
        $this->assertStringContainsString('no completion target set', ClearanceGate::describe($gate['missing'][0]));
    }

    public function test_d_all_targets_met_is_ready_for_review(): void
    {
        $gate = ClearanceGate::evaluate(
            [$this->rx('rx1', 2), $this->rx('rx2', 1, 'wallSit')],
            [$this->session('rx1'), $this->session('rx1'), $this->session('rx1'), $this->session('rx2')],
            [],
        );

        $this->assertSame(ClearanceGate::READY_FOR_REVIEW, $gate['state']);
        $this->assertSame([], $gate['missing']);
        $this->assertSame([
            ['prescriptionId' => 'rx1', 'exerciseType' => 'kneeExtension', 'finished' => 3, 'required' => 2],
            ['prescriptionId' => 'rx2', 'exerciseType' => 'wallSit', 'finished' => 1, 'required' => 1],
        ], ClearanceGate::snapshot($gate));
    }

    public function test_e_met_but_restricted_exercise_blocks(): void
    {
        $gate = ClearanceGate::evaluate(
            [$this->rx('rx1', 1), $this->rx('rx2', 1, 'wallSit')],
            [$this->session('rx1'), $this->session('rx2')],
            ['wallSit'],
        );

        $this->assertSame(ClearanceGate::IN_PROGRESS, $gate['state']);
        $this->assertCount(1, $gate['missing']);
        $this->assertSame('rx2', $gate['missing'][0]['prescriptionId']);
        $this->assertTrue($gate['missing'][0]['restricted']);
        $this->assertSame(ClearanceGate::REASON_RESTRICTED, $gate['missing'][0]['reason']);
        $this->assertStringContainsString('restricted by clinician', ClearanceGate::describe($gate['missing'][0]));
    }

    public function test_f_sessions_for_other_or_no_prescription_do_not_count(): void
    {
        $gate = ClearanceGate::evaluate(
            [$this->rx('rx1', 2)],
            [$this->session('rx1'), $this->session('rxOther'), $this->session(null), $this->session('')],
            [],
        );

        $this->assertSame(ClearanceGate::IN_PROGRESS, $gate['state']);
        $this->assertSame(1, $gate['missing'][0]['finished']);
    }

    public function test_g_inactive_prescriptions_are_ignored(): void
    {
        // A stopped prescription with no target doesn't block...
        $gate = ClearanceGate::evaluate(
            [$this->rx('rx1', 1), $this->rx('rxStopped', null, active: false)],
            [$this->session('rx1')],
            [],
        );
        $this->assertSame(ClearanceGate::READY_FOR_REVIEW, $gate['state']);
        $this->assertCount(1, $gate['requirements']);

        // ...and only stopped prescriptions means there is no program.
        $this->assertSame(ClearanceGate::NO_PROGRAM, ClearanceGate::evaluate([$this->rx('rxStopped', 1, active: false)], [$this->session('rxStopped')], [])['state']);
    }

    public function test_out_of_range_targets_count_as_no_target(): void
    {
        foreach ([0, 501, -3] as $bad) {
            $gate = ClearanceGate::evaluate([$this->rx('rx1', $bad)], [$this->session('rx1')], []);
            $this->assertSame(ClearanceGate::REASON_NO_TARGET, $gate['missing'][0]['reason'], "target {$bad}");
        }
    }
}
