function efficientnet(block_configs::AbstractVector{<:Tuple},
                      residual_fns::AbstractVector; inplanes::Integer,
                      scalings::NTuple{2, Real} = (1, 1),
                      headplanes::Integer = block_configs[end][3] * 4,
                      norm_layer = BatchNorm, dropout_rate = nothing,
                      inchannels::Integer = 3, nclasses::Integer = 1000)
    layers = []
    # stem of the model
    append!(layers,
            conv_norm((3, 3), inchannels, _round_channels(inplanes * scalings[1], 8),
                      swish; norm_layer, stride = 2, pad = SamePad()))
    # building inverted residual blocks
    get_layers, block_repeats = mbconv_stack_builder(block_configs, residual_fns;
                                                     inplanes, scalings, norm_layer)
    append!(layers, cnn_stages(get_layers, block_repeats, +))
    # building last layers
    append!(layers,
            conv_norm((1, 1), _round_channels(block_configs[end][2] * scalings[1], 8),
                      headplanes, swish; pad = SamePad()))
    return Chain(Chain(layers...), create_classifier(headplanes, nclasses; dropout_rate))
end
