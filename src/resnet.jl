basicblock(inplanes, outplanes, downsample = false) = downsample ?
  Chain(conv_bn((3, 3), inplanes, outplanes[1]; stride=2, pad=1, usebias=false)...,
        conv_bn((3, 3), outplanes[1], outplanes[2]; stride=1, pad=1, usebias=false)...) :
  Chain(conv_bn((3, 3), inplanes, outplanes[1]; stride=1, pad=1, usebias=false)...,
        conv_bn((3, 3), outplanes[1], outplanes[2]; stride=1, pad=1, usebias=false)...)

bottleneck(inplanes, outplanes, downsample = false) = downsample ?
  Chain(conv_bn((1, 1), inplanes, outplanes[1]; stride=2, usebias=false)...,
        conv_bn((3, 3), outplanes[1], outplanes[2]; stride=1, pad=1, usebias=false)...,
        conv_bn((1, 1), outplanes[2], outplanes[3]; stride=1, usebias=false)...) :
  Chain(conv_bn((1, 1), inplanes, outplanes[1]; stride=1, usebias=false)...,
        conv_bn((3, 3), outplanes[1], outplanes[2]; stride=1, pad=1, usebias=false)...,
        conv_bn((1, 1), outplanes[2], outplanes[3]; stride=1, usebias=false)...)

skip_projection(inplanes, outplanes, downsample = false) = downsample ? 
  Chain(conv_bn((1, 1), inplanes, outplanes; stride=2, usebias=false)...) :
  Chain(conv_bn((1, 1), inplanes, outplanes; stride=1, usebias=false)...)

# array -> PaddedView(0, array, outplanes) for zero padding arrays
function skip_identity(inplanes, outplanes)
  if outplanes[end] > inplanes
    return Chain(MaxPool((1, 1), stride = 2),
                 y -> cat(y, zeros(eltype(y),
                                   size(y, 1),
                                   size(y, 2),
                                   outplanes[end] - inplanes, size(y, 4)); dims = 3))
  else
    return identity
  end
end

function resnet(block, shortcut_config, channel_config, block_config)
  inplanes = 64
  baseplanes = 64
  layers = []
  append!(layers, conv_bn((7, 7), 3, inplanes; stride=2, pad=(3, 3)))
  push!(layers, MaxPool((3, 3), stride=(2, 2), pad=(1, 1)))
  for (i, nrepeats) in enumerate(block_config)
    outplanes = baseplanes .* channel_config
    if shortcut_config == :A
      push!(layers, Parallel(+, block(inplanes, outplanes, i != 1),
                                skip_identity(inplanes, outplanes)))
    elseif shortcut_config == :B || shortcut_config == :C
      push!(layers, Parallel(+, block(inplanes, outplanes, i != 1),
                                skip_projection(inplanes, outplanes[end], i != 1)))
    end
    inplanes = outplanes[end]
    for j in 2:nrepeats
      if shortcut_config == :A || shortcut_config == :B
        push!(layers, Parallel(+, block(inplanes, outplanes, false),
                                  skip_identity(inplanes, outplanes[end])))
      elseif shortcut_config == :C
        push!(layers, Parallel(+, block(inplanes, outplanes, false),
                                  skip_projection(inplanes, outplanes, false)))
      end
      inplanes = outplanes[end]
    end
    baseplanes *= 2
  end
  push!(layers, AdaptiveMeanPool((1, 1)))
  push!(layers, flatten)
  push!(layers, Dense(inplanes, 1000))

  return Chain(layers...)
end

const resnet_config =
  Dict("resnet18" => ([1, 1], [2, 2, 2, 2]),
      "resnet34" => ([1, 1], [3, 4, 6, 3]),
      "resnet50" => ([1, 1, 4], [3, 4, 6, 3]),
      "resnet101" => ([1, 1, 4], [3, 4, 23, 3]),
      "resnet152" => ([1, 1, 4], [3, 8, 36, 3]))

function resnet18(; pretrain=false)
  model = resnet(basicblock, :A, resnet_config["resnet18"]...)

  pretrain && pretrain_error("resnet18")
  return model
end

function resnet34(; pretrain=false)
  model = resnet(basicblock, :A, resnet_config["resnet34"]...)

  pretrain && pretrain_error("resnet34")
  return model
end

function resnet50(; pretrain=false)
  model = resnet(bottleneck, :B, resnet_config["resnet50"]...)

  pretrain && Flux.loadparams!(model, weights("resnet50"))
end

function resnet101(; pretrain=false)
  model = resnet(bottleneck, :B, resnet_config["resnet101"]...)

  pretrain && pretrain_error("resnet101")
  return model
end

function resnet152(; pretrain=false)
  model = resnet(bottleneck, :B, resnet_config["resnet152"]...)

  pretrain && pretrain_error("resnet152")
  return model
end