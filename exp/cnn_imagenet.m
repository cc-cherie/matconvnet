function cnn_imagenet(varargin)
% CNN_IMAGENET   Demonstrates training a CNN on ImageNet

run(fullfile(fileparts(mfilename('fullpath')), '../matlab/vl_setupnn.m')) ;

opts.dataDir = 'data/imagenet12' ;
opts.expDir = 'data/imagenet12-baseline' ;
opts.imdbPath = fullfile(opts.expDir, 'imdb.mat');
opts.lite = false ;
opts.numFetchThreads = 0 ;
opts.train.batchSize = 256 ;
opts.train.numEpochs = 100 ;
opts.train.continue = true ;
opts.train.useGpu = false ;
opts.train.prefetch = false ;
opts.train.learningRate = [0.001*ones(1, 30) 0.0001*ones(1,10) 0.00001*ones(1,10)] ;
opts.train.expDir = opts.expDir ;
opts = vl_argparse(opts, varargin) ;

% -------------------------------------------------------------------------
%                                                   Database initialization
% -------------------------------------------------------------------------

if exist(opts.imdbPath)
  imdb = load(opts.imdbPath) ;
else
  imdb = cnn_imagenet_setup_data('dataDir', opts.dataDir, 'lite', opts.lite) ;
  mkdir(opts.expDir) ;
  save(opts.imdbPath, '-struct', 'imdb') ;
end

% -------------------------------------------------------------------------
%                                                    Network initialization
% -------------------------------------------------------------------------

net = initializeNetwork(opts) ;

% compute the average image
averageImagePath = fullfile(opts.expDir, 'average.mat') ;
if exist(averageImagePath)
  load(averageImagePath, 'averageImage') ;
else
  train = find(imdb.images.set == 1) ;
  bs = 256 ;
  fn = getBatchWrapper(net.normalization, opts.numFetchThreads) ;
  for t=1:bs:numel(train)
    batch_time = tic ;
    batch = train(t:min(t+bs-1, numel(train))) ;
    fprintf('computing average image: processing batch starting with image %d ...', batch(1)) ;
    temp = fn(imdb, batch) ;
    im{t} = mean(temp, 4) ;
    batch_time = toc(batch_time) ;
    fprintf(' %.2f s (%.1f images/s)\n', batch_time, numel(batch)/ batch_time) ;
  end
  averageImage = mean(cat(4, im{:}),4) ;
  save(averageImagePath, 'averageImage') ;
end

net.normalization.averageImage = averageImage ;
clear averageImage im temp ;

% -------------------------------------------------------------------------
%                                               Stochastic gradient descent
% -------------------------------------------------------------------------

fn = getBatchWrapper(net.normalization, opts.numFetchThreads) ;

[net,info] = cnn_train(net, imdb, fn, opts.train, 'conserveMemory', true) ;

% -------------------------------------------------------------------------
function fn = getBatchWrapper(opts, numThreads)
% -------------------------------------------------------------------------
fn = @(imdb,batch) getBatch(imdb,batch,opts,numThreads) ;

% -------------------------------------------------------------------------
function [im,labels] = getBatch(imdb, batch, opts, numThreads)
% -------------------------------------------------------------------------
images = strcat([imdb.imageDir '/'], imdb.images.name(batch)) ;
im = cnn_imagenet_get_batch(images, opts, ...
                            'numThreads', numThreads, ...
                            'prefetch', nargout == 0) ;
labels = imdb.images.label(batch) ;

% -------------------------------------------------------------------------
function net = initializeNetwork(opt)
% -------------------------------------------------------------------------

scal = 1 ;

net.layers = {} ;

% Block 1
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(11, 11, 3, 96, 'single'), ...
                           'biases', ones(1, 96, 'single'), ...
                           'stride', 4, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
    'method', 'max', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'normalize', ...
                           'param', [5 1 0.0001/5 0.75], ...
                           'stride', 2, ...
                           'pad', 0) ;

% Block 2
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(5, 5, 48, 256, 'single'), ...
                           'biases', ones(1, 256, 'single'), ...
                           'stride', 1, ...
                           'pad', 2) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
  'method', 'max', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'normalize', ...
                           'param', [5 1 0.0001/5 0.75], ...
                           'stride', 2, ...
                           'pad', 0) ;

% Block 3
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(3,3,256,384,'single'), ...
                           'biases', ones(1,384,'single'), ...
                           'stride', 1, ...
                           'pad', 1) ;
net.layers{end+1} = struct('type', 'relu') ;

% Block 4
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(3,3,192,384,'single'), ...
                           'biases', ones(1,384,'single'), ...
                           'stride', 1, ...
                           'pad', 1) ;
net.layers{end+1} = struct('type', 'relu') ;

% Block 5
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(3,3,192,256,'single'), ...
                           'biases', ones(1,256,'single'), ...
                           'stride', 1, ...
                           'pad', 1) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'pool', ...
    'method', 'max', ...
                           'pool', [3 3], ...
                           'stride', 2, ...
                           'pad', 0) ;

% Block 6
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(6,6,256,4096,'single'),...
                           'biases', ones(1,4096,'single'), ...
                           'stride', 1, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'dropout', ...
                           'rate', 0.5) ;

% Block 7
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(1,1,4096,4096,'single'),...
                           'biases', ones(1,4096,'single'), ...
                           'stride', 1, ...
                           'pad', 0) ;
net.layers{end+1} = struct('type', 'relu') ;
net.layers{end+1} = struct('type', 'dropout', ...
                           'rate', 0.5) ;

% Block 8
net.layers{end+1} = struct('type', 'conv', ...
                           'filters', 0.01/scal * randn(1,1,4096,1000,'single'), ...
                           'biases', zeros(1, 1000, 'single'), ...
                           'stride', 1, ...
                           'pad', 0) ;

% Block 9
net.layers{end+1} = struct('type', 'softmaxloss') ;

% Other details
net.normalization.imageSize = [227, 227] ;
net.normalization.interpolation = 'bilinear' ;
net.normalization.border = 255 - net.normalization.imageSize ;
net.normalization.averageImage = [] ;

