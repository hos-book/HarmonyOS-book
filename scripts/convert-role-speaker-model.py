import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

import torch
from transformers import BertConfig, BertForQuestionAnswering


class RoleQuestionAnsweringExport(torch.nn.Module):
    def __init__(self, model: BertForQuestionAnswering) -> None:
        super().__init__()
        self.model = model

    def forward(self, input_ids: torch.Tensor, token_type_ids: torch.Tensor,
                attention_mask: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        result = self.model(
            input_ids=input_ids,
            token_type_ids=token_type_ids,
            attention_mask=attention_mask,
            return_dict=False,
        )
        return result[0], result[1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-dir', required=True, type=Path)
    parser.add_argument('--checkpoint', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--converter', required=True, type=Path)
    args = parser.parse_args()

    torch.set_num_threads(2)
    config = BertConfig.from_pretrained(str(args.model_dir))
    config.layer_norm_eps = 1e-5
    config._attn_implementation = 'eager'
    model = BertForQuestionAnswering(config)
    state = torch.load(args.checkpoint, map_location='cpu', weights_only=True)
    state.pop('bert.pooler.dense.weight')
    state.pop('bert.pooler.dense.bias')
    model.load_state_dict(state)
    model.eval()
    wrapper = RoleQuestionAnsweringExport(model)
    ids = torch.zeros((1, 512), dtype=torch.int32)
    token_types = torch.zeros((1, 512), dtype=torch.int32)
    attention = torch.ones((1, 512), dtype=torch.int32)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='role-speaker-') as temporary:
        onnx_path = Path(temporary) / 'role-speaker.onnx'
        input_names = ['input_ids', 'token_type_ids', 'attention_mask']
        output_names = ['start_logits', 'end_logits']
        with torch.inference_mode():
            torch.onnx.export(
                wrapper, (ids, token_types, attention), str(onnx_path),
                input_names=input_names, output_names=output_names,
                opset_version=13, do_constant_folding=True, dynamo=False,
            )
        output_prefix = Path(temporary) / 'csi-v1-generic'
        subprocess.run([
            str(args.converter.resolve()), '--fmk=ONNX', f'--modelFile={onnx_path}',
            f'--outputFile={output_prefix}', '--saveType=MINDIR_LITE',
            '--fp16=on', '--optimize=general',
        ], cwd=temporary, check=True)
        shutil.move(str(output_prefix.with_suffix('.ms')), str(args.output.resolve()))
    print(f'Created portable NPU/CPU model: {args.output}', flush=True)


if __name__ == '__main__':
    main()
