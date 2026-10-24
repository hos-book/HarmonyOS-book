"""Apply an FP32 compatibility recheck only in the external package build."""
import json


def apply_calibration_patch(project, patch_id):
    if patch_id != 'fp32-nnrt-recheck-v3':
        raise ValueError('Unknown comic AI integration patch')
    source = project / 'aiengine/src/main/ets/core/reader/ComicColorInference.ets'
    text = source.read_text(encoding='utf-8')
    changes = [
        (
            '    let valid = ComicColorInference.matches(accelerated.colors, reference.colors, canvas.width, canvas.height);',
            '    let valid = ComicColorInference.matches(accelerated.colors, reference.colors, canvas.width, canvas.height);\n'
            '    let validationReference = reference;\n'
            "    let validation = 'fp16';\n"
            '    // Preserve the upstream fast path. Some devices have a drifting CPU FP16\n'
            '    // reference; recheck a mismatch with FP32 before rejecting NNRT.\n'
            '    if (!valid) {\n'
            "      const validationContext: mindSporeLite.Context = { target: ['cpu'], cpu: { threadNum: 4 } };\n"
            '      try {\n'
            '        validationReference = await ComicColorInference.execute(job.modelPath, padded, canvas.width, canvas.height,\n'
            '          validationContext, check);\n'
            '        check();\n'
            "        validation = 'fp32-recheck';\n"
            '        valid = ComicColorInference.matches(accelerated.colors, validationReference.colors, canvas.width, canvas.height);\n'
            '      } catch (error) {\n'
            '        check();\n'
            "        validation = 'fp32-unavailable';\n"
            '      }\n'
            '    }'
        ),
        (
            '        valid = ComicColorInference.matches(accelerated.colors, reference.colors, canvas.width, canvas.height);',
            '        valid = ComicColorInference.matches(accelerated.colors, validationReference.colors, canvas.width, canvas.height);'
        ),
        ('cpu=${reference.totalMs}ms matches=${valid} selected=${profile.backend}',
         'cpu=${reference.totalMs}ms validation=${validation} validationMs=${validationReference.totalMs}ms matches=${valid} selected=${profile.backend}')
    ]
    for before, after in changes:
        if text.count(before) != 1:
            raise ValueError('Pinned engine calibration code changed; review the patch before upgrading')
        text = text.replace(before, after, 1)
    source.write_text(text, encoding='utf-8')
    # Persistent decisions must be invalidated whenever our calibration rules change.
    policy = project / 'aiengine/src/main/ets/core/reader/ComicColorProfilePolicy.ts'
    policy_text = policy.read_text(encoding='utf-8')
    contract = "static readonly CONTRACT: string = 'nnrt-calibration-v2';"
    if policy_text.count(contract) != 1:
        raise ValueError('Pinned engine profile contract changed; review the patch before upgrading')
    profile_contract = f'nnrt-calibration-v2:{patch_id}'
    policy.write_text(policy_text.replace(contract, f"static readonly CONTRACT: string = '{profile_contract}';", 1), encoding='utf-8')
    marker = project / 'aiengine/src/main/resources/rawfile/comic-colorizer/host-integration.json'
    marker.write_text(json.dumps({'patch': patch_id, 'accuracyReference': 'cpu-fp16-then-fp32-on-mismatch',
                                 'performanceReference': 'cpu-fp16', 'maeThreshold': 0.03,
                                 'profileContract': profile_contract}, indent=2) + '\n', encoding='utf-8')
