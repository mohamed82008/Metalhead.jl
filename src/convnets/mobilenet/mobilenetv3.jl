"""
    mobilenetv3(width_mult::Number, configs::Vector{<:Tuple};
                max_width::Integer = 1024, inchannels::Integer = 3,
                nclasses::Integer = 1000)

Create a MobileNetv3 model.
([reference](https://arxiv.org/abs/1905.02244)).

# Arguments

  - `width_mult`: Controls the number of output feature maps in each block
    (with 1.0 being the default in the paper;
    this is usually a value between 0.1 and 1.4)

  - `configs`: a "list of tuples" configuration for each layer that details:
    
      + `k::Integer` - The size of the convolutional kernel
      + `c::Float` - The multiplier factor for deciding the number of feature maps in the hidden layer
      + `t::Integer` - The number of output feature maps for a given block
      + `r::Integer` - The reduction factor (`>= 1` or `nothing` to skip) for squeeze and excite layers
      + `s::Integer` - The stride of the convolutional kernel
      + `a` - The activation function used in the bottleneck (typically `hardswish` or `relu`)
  - `inchannels`: The number of input channels.
  - `max_width`: The maximum number of feature maps in any layer of the network
  - `nclasses`: the number of output classes
"""
function mobilenetv3(width_mult::Number, configs::Vector{<:Tuple};
                     max_width::Integer = 1024, inchannels::Integer = 3,
                     nclasses::Integer = 1000)
    # building first layer
    inplanes = _round_channels(16 * width_mult, 8)
    layers = []
    append!(layers,
            conv_norm((3, 3), inchannels, inplanes, hardswish; pad = 1, stride = 2,
                      bias = false))
    explanes = 0
    # building inverted residual blocks
    for (k, t, c, r, a, s) in configs
        # inverted residual layers
        outplanes = _round_channels(c * width_mult, 8)
        explanes = _round_channels(inplanes * t, 8)
        push!(layers,
              invertedresidual((k, k), inplanes, explanes, outplanes, a;
                               stride = s, reduction = r))
        inplanes = outplanes
    end
    # building last layers
    output_channel = max_width
    output_channel = width_mult > 1.0 ? _round_channels(output_channel * width_mult, 8) :
                     output_channel
    append!(layers, conv_norm((1, 1), inplanes, explanes, hardswish; bias = false))
    classifier = Chain(AdaptiveMeanPool((1, 1)), MLUtils.flatten,
                       Dense(explanes, output_channel, hardswish),
                       Dropout(0.2),
                       Dense(output_channel, nclasses))
    return Chain(Chain(layers...), classifier)
end

# Layer configurations for small and large models for MobileNetv3
const MOBILENETV3_CONFIGS = Dict(:small => [
                                     # k, t, c, SE, a, s
                                     (3, 1, 16, 4, relu, 2),
                                     (3, 4.5, 24, nothing, relu, 2),
                                     (3, 3.67, 24, nothing, relu, 1),
                                     (5, 4, 40, 4, hardswish, 2),
                                     (5, 6, 40, 4, hardswish, 1),
                                     (5, 6, 40, 4, hardswish, 1),
                                     (5, 3, 48, 4, hardswish, 1),
                                     (5, 3, 48, 4, hardswish, 1),
                                     (5, 6, 96, 4, hardswish, 2),
                                     (5, 6, 96, 4, hardswish, 1),
                                     (5, 6, 96, 4, hardswish, 1),
                                 ],
                                 :large => [
                                     # k, t, c, SE, a, s
                                     (3, 1, 16, nothing, relu, 1),
                                     (3, 4, 24, nothing, relu, 2),
                                     (3, 3, 24, nothing, relu, 1),
                                     (5, 3, 40, 4, relu, 2),
                                     (5, 3, 40, 4, relu, 1),
                                     (5, 3, 40, 4, relu, 1),
                                     (3, 6, 80, nothing, hardswish, 2),
                                     (3, 2.5, 80, nothing, hardswish, 1),
                                     (3, 2.3, 80, nothing, hardswish, 1),
                                     (3, 2.3, 80, nothing, hardswish, 1),
                                     (3, 6, 112, 4, hardswish, 1),
                                     (3, 6, 112, 4, hardswish, 1),
                                     (5, 6, 160, 4, hardswish, 2),
                                     (5, 6, 160, 4, hardswish, 1),
                                     (5, 6, 160, 4, hardswish, 1),
                                 ])

"""
    MobileNetv3(mode::Symbol; width_mult::Number = 1, pretrain::Bool = false,
                inchannels::Integer = 3, nclasses::Integer = 1000)

Create a MobileNetv3 model with the specified configuration.
([reference](https://arxiv.org/abs/1905.02244)).
Set `pretrain = true` to load the model with pre-trained weights for ImageNet.

# Arguments

  - `mode`: :small or :large for the size of the model (see paper).
  - `width_mult`: Controls the number of output feature maps in each block
    (with 1.0 being the default in the paper;
    this is usually a value between 0.1 and 1.4)
  - `pretrain`: whether to load the pre-trained weights for ImageNet
  - `inchannels`: The number of channels in the input.
  - `nclasses`: the number of output classes

See also [`Metalhead.mobilenetv3`](#).
"""
struct MobileNetv3
    layers::Any
end
@functor MobileNetv3

function MobileNetv3(mode::Symbol; width_mult::Number = 1, pretrain::Bool = false,
                     inchannels::Integer = 3, nclasses::Integer = 1000)
    _checkconfig(mode, [:small, :large])
    max_width = (mode == :large) ? 1280 : 1024
    layers = mobilenetv3(width_mult, MOBILENETV3_CONFIGS[mode]; inchannels, max_width,
                         nclasses)
    if pretrain
        loadpretrain!(layers, string("MobileNetv3", mode))
    end
    return MobileNetv3(layers)
end

(m::MobileNetv3)(x) = m.layers(x)

backbone(m::MobileNetv3) = m.layers[1]
classifier(m::MobileNetv3) = m.layers[2]
