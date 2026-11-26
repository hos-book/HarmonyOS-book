"""Convert the exported SLBR model to MindSpore Lite for HarmonyOS NNRT."""
import argparse
from pathlib import Path
import subprocess
import tempfile

import numpy as np
import onnx
from onnx import helper, numpy_helper
from onnxruntime.tools.symbolic_shape_infer import SymbolicShapeInference


def spatial_resizes(model):
    """Express half-pixel bilinear resize as fixed spatial gathers and blends."""
    inferred = SymbolicShapeInference.infer_shapes(model)
    shapes = {value.name: [dim.dim_value for dim in value.type.tensor_type.shape.dim]
              for value in list(inferred.graph.value_info) + list(inferred.graph.input)}
    nodes = []
    for node in model.graph.node:
        if node.op_type == 'Resize':
            current = node.input[0]
            for axis in (2, 3):
                size = shapes[node.output[0]][axis]
                original = shapes[node.input[0]][axis]
                positions = (np.arange(size, dtype=np.float32) + 0.5) * original / size - 0.5
                lower = np.floor(positions).astype(np.int64)
                weights = positions - lower
                prefix = node.name + f'/axis_{axis}'
                weight_shape = [1, 1, 1, 1]
                weight_shape[axis] = size
                for suffix, data in (
                    ('lower', np.clip(lower, 0, original - 1)),
                    ('upper', np.clip(lower + 1, 0, original - 1)),
                    ('weight', weights.astype(np.float32).reshape(weight_shape)),
                ):
                    model.graph.initializer.append(numpy_helper.from_array(data, prefix + '/' + suffix))
                low = prefix + '/low'
                high = prefix + '/high'
                delta = prefix + '/delta'
                blend = prefix + '/blend'
                output = node.output[0] if axis == 3 else prefix + '/output'
                nodes.extend([
                    helper.make_node('Gather', [current, prefix + '/lower'], [low], name=low, axis=axis),
                    helper.make_node('Gather', [current, prefix + '/upper'], [high], name=high, axis=axis),
                    helper.make_node('Sub', [high, low], [delta], name=delta),
                    helper.make_node('Mul', [delta, prefix + '/weight'], [blend], name=blend),
                    helper.make_node('Add', [low, blend], [output], name=output),
                ])
                current = output
        else:
            nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)


def bounded_values(model):
    """Express Clip bounds through equivalent ReLU and scalar arithmetic."""
    nodes = []
    for node in model.graph.node:
        if node.op_type == 'Clip':
            current = node.input[0]
            bounds = [(op, node.input[index]) for index, op in ((1, 'Max'), (2, 'Min'))
                      if len(node.input) > index and node.input[index]]
            for index, (op, bound) in enumerate(bounds):
                output = node.output[0] if index == len(bounds) - 1 else node.name + '/lower_bound'
                delta = node.name + '/' + op + '_delta'
                positive = node.name + '/' + op + '_positive'
                operands = [current, bound] if op == 'Max' else [bound, current]
                nodes.append(helper.make_node('Sub', operands, [delta], name=delta))
                nodes.append(helper.make_node('Relu', [delta], [positive], name=positive))
                nodes.append(helper.make_node('Add' if op == 'Max' else 'Sub',
                                              [bound, positive], [output], name=node.name + '/' + op))
                current = output
        else:
            nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)


def fixed_reshapes(model):
    """Resolve static squeeze axes before the NNRT driver imports the graph."""
    inferred = onnx.shape_inference.infer_shapes(model)
    shapes = {value.name: [dim.dim_value for dim in value.type.tensor_type.shape.dim]
              for value in inferred.graph.value_info}
    for node in model.graph.node:
        if node.op_type in ('Squeeze', 'Unsqueeze'):
            shape_name = node.name + '/fixed_shape'
            model.graph.initializer.append(numpy_helper.from_array(
                np.array(shapes[node.output[0]], dtype=np.int64), shape_name))
            source = node.input[0]
            node.op_type = 'Reshape'
            del node.input[:]
            node.input.extend([source, shape_name])
            del node.attribute[:]


def spatial_attention(model):
    """Express the two attention centers as an equivalent NCHW weighted sum."""
    by_name = {node.name: node for node in model.graph.node}
    replacements = {}
    removed = set()
    for stage in range(3):
        prefix = f'/network/coarse_decoder/up_convs_mask.{stage}/self_calibrated/'
        scores = by_name[prefix + 'Concat_2'].input
        centers = by_name[prefix + 'Concat_3'].input
        shape_node = by_name[prefix + 'Constant_30']
        channels = int(numpy_helper.to_array(shape_node.attribute[0].t)[3])
        target = by_name[prefix + 'Transpose_1'].output[0]
        shape_name = prefix + 'spatial_center_shape'
        model.graph.initializer.append(numpy_helper.from_array(
            np.array([1, channels, 1, 1], dtype=np.int64), shape_name))
        nodes = []
        products = []
        for center in range(2):
            reshaped = prefix + f'spatial_center_{center}'
            product = prefix + f'spatial_product_{center}'
            nodes.append(helper.make_node('Reshape', [centers[center], shape_name],
                                          [reshaped], name=reshaped))
            nodes.append(helper.make_node('Mul', [reshaped, scores[center]],
                                          [product], name=product))
            products.append(product)
        nodes.append(helper.make_node('Add', products, [target], name=prefix + 'spatial_attention'))
        replacements[prefix + 'Transpose_1'] = nodes
        removed.update(prefix + name for name in
                       ('Transpose', 'Reshape_2', 'Reshape_3', 'MatMul', 'Reshape_4'))
    nodes = []
    for node in model.graph.node:
        if node.name in replacements:
            nodes.extend(replacements[node.name])
        elif node.name not in removed:
            nodes.append(node)
    del model.graph.node[:]
    model.graph.node.extend(nodes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--converter', type=Path, required=True)
    args = parser.parse_args()
    model = onnx.load(args.input)
    spatial_resizes(model)
    fixed_reshapes(model)
    spatial_attention(model)
    bounded_values(model)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='comic-watermark-convert-') as directory:
        intermediate = Path(directory) / 'slbr-spatial.onnx'
        onnx.save(model, intermediate)
        subprocess.run([str(args.converter), '--fmk=ONNX', f'--modelFile={intermediate}',
                        f'--outputFile={args.output.with_suffix("")}',
                        '--inputShape=image:1,3,256,256', '--inputDataFormat=NCHW',
                        '--outputDataFormat=NCHW', '--saveType=MINDIR_LITE'], check=True)
    print(args.output.with_suffix('.ms'))


if __name__ == '__main__':
    main()
