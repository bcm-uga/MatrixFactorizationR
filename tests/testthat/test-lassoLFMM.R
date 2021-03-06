library(testthat)
context("lassoLFMM")

test_that("lassoLFMM_heuristic_gamma and lassoLFMM_heuristic_lambda_range", {

  K <- 3
  dat <- lfmm_sampler(n = 100, p = 1000, K = K,
                      outlier.prop = 0.1,
                      cs = c(0.8),
                      sigma = 0.2,
                      B.sd = 1.0,
                      U.sd = 1.0,
                      V.sd = 1.0)


  m <- lassoLFMM(K = 3)

  params <- lassoLFMM_heuristic_gamma_lambda_range(m, dat)

  expect_equal(length(params$lambda.range), 100)

})

test_that("compute_soft_svd", {


  D_thau <- function(X, gamma) {
    m <- list()
    svd.res <- svd(X, nu = 0, nv = 0) # compute only singular value
    aux <- svd.res$d - gamma
    Sigma <- diag(aux[aux > 0.0])
    m$K <- ncol(Sigma)

    svd.res <- svd(X, nu = m$K, nv = m$K)
    m$d <- aux[aux > 0.0]
    m$U <- svd.res$u %*% Sigma
    m$V <- svd.res$v
    m
  }

  K <- 3
  dat <- lfmm_sampler(n = 100, p = 1000, K = K,
                      outlier.prop = 0.1,
                      cs = c(0.8),
                      sigma = 0.2,
                      B.sd = 1.0,
                      U.sd = 1.0,
                      V.sd = 1.0)

  ## compute gamma
  m <- lassoLFMM(K = 3)
  params <- lassoLFMM_heuristic_gamma_lambda_range(m, dat)

  ## RSpectra
  Af <- function(x, args) {
    dat$productY(x)
  }
  Atransf <- function(x, args) {
    dat$productYt(x)
  }
  res.rspectra <- compute_svd_soft(Af, Atransf, params$gamma, K, dim = c(nrow(dat$Y), ncol(dat$Y)))
  W.rspectra <- tcrossprod(res.rspectra$u %*% diag(res.rspectra$d),
                           res.rspectra$v)

  ## R
  res <- D_thau(dat$Y, params$gamma)
  dim(res$U)
  W.r <- tcrossprod(res$U,res$V)

  ## comp
  expect_lt(mean(abs(W.r - W.rspectra)), 1e-10)
  expect_lt(mean(abs(res$d - res.rspectra$d)), 1e-10)

})


test_that("lassoLFMM main loop", {

  K <- 3
  dat <- lfmm_sampler(n = 100, p = 1000, K = K,
                      outlier.prop = 0.1,
                      cs = c(0.8),
                      sigma = 0.2,
                      B.sd = 1.0,
                      U.sd = 1.0,
                      V.sd = 1.0)
  dat.list <- list(G = dat$Y, X = dat$X)
  dat$missing.ind <- which(is.na(dat$Y))

  ## compute gamma
  m <- lassoLFMM(K = 3,
                 nozero.prop = 0.1,
                 lambda.num = 20,
                 lambda.min.ratio = 0.001)
  params <- lassoLFMM_heuristic_gamma_lambda_range(m, dat)

  ## init B
  if (is.null(m$B)) {
    m$B <- matrix(0.0, ncol(dat$Y), ncol(dat$X))
  }

  ## init U and V
  if (is.null(m$U)) {
    m$U <- matrix(0.0, nrow(dat$Y), m$K)
  }
  if (is.null(m$V)) {
    m$V <- matrix(0.0, ncol(dat$Y), m$K)
  }

  ## main loop
  lambda <- params$lambda.range[20]
  relative.err.epsilon = 1e-6
  it.max <- 100

  ## lfmm
  m <- lassoLFMM_loop(m, dat, params$gamma, lambda, relative.err.epsilon, it.max)

  ## why err decrease and then increase ??
  ## m <- res.cpp
  ## res.cpp <- lassoLFMM_main(dat$Y, dat$X,
  ##                           params$gamma, lambda,
  ##                           relative.err.epsilon,
  ##                           it.max,
  ##                           m$U,
  ##                           m$V,
  ##                           m$B)
  ## ok it not recompute all
  expect_equal(dim(m$U), c(100, 3))
  expect_equal(dim(m$V), c(1000, 3))
  expect_equal(dim(m$B), c(1000, 1))

  ## ThesisRpackage implementation
  skip_if_not_installed("ThesisRpackage")
  futile.logger::flog.threshold(futile.logger::TRACE, name = "ThesisRpackage")
  res.r <- ThesisRpackage::LassoLFMMMethod(K = NULL,
                                           gamma = params$gamma,
                                           it.max = it.max,
                                           err.max = relative.err.epsilon,
                                           lambda = lambda,
                                           center = FALSE)
  res.r <- ThesisRpackage::fit(res.r , dat.list)

  ## comp
  W.r <- tcrossprod(res.r$U, res.r$V)
  W.cpp <- tcrossprod(m$U, m$V)
  expect_lte(mean(abs(W.r - W.cpp)), 1e-10)
  expect_lte(mean(abs(m$B - t(res.r$B))), 1e-10)
  expect_equal(mean(m$B != 0), mean(res.r$B != 0))

})

test_that("lassoLFMM", {

  K <- 3
  dat <- lfmm_sampler(n = 100, p = 1000, K = K,
                      outlier.prop = 0.1,
                      cs = c(0.8),
                      sigma = 0.2,
                      B.sd = 1.0,
                      U.sd = 1.0,
                      V.sd = 1.0)
  dat.list <- list(G = dat$Y, X = dat$X)

  ## lassoLFMM
  m <- lassoLFMM(K = 3,
                 nozero.prop = 0.1,
                 lambda.num = 20,
                 lambda.min.ratio = 0.001)
  m <- lfmm_fit(m, dat,
                                it.max = 100, relative.err.epsilon = 1e-4)

  skip("do not give same result") ## I think this is because they do not stop with same lambda... todo
  skip_if_not_installed("ThesisRpackage")
  futile.logger::flog.threshold(futile.logger::TRACE, name = "ThesisRpackage")
  m.ThesisRpackage <- ThesisRpackage::finalLfmmLassoMethod(K = 3, sparse.prop = 0.1,
                                                           lambda.num = 20, lambda.min.ratio = 0.001)
  m.ThesisRpackage$center <- FALSE
  m.ThesisRpackage <- ThesisRpackage::fit(m.ThesisRpackage, dat.list)


  ## comp
  W <- tcrossprod(m$U, m$V)
  W.thesis <- tcrossprod(m.ThesisRpackage$U, m.ThesisRpackage$V)
  expect_lte(mean(abs(W - W.thesis)), 1e-10)
  mean(m$B != 0)
  mean(m.ThesisRpackage$B != 0)
  expect_lte(mean(abs(m$B - t(m.ThesisRpackage$B))), 1e-10)

})

test_that("lassoLFMM with missing value", {

  skip("todo")
  K <- 3
  n <- 100
  p <- 1000
  dat <- lfmm_sampler(n = n, p = p, K = K,
                      outlier.prop = 0.1,
                      cs = c(0.8),
                      sigma = 0.2,
                      B.sd = 1.0,
                      U.sd = 1.0,
                      V.sd = 1.0)

  ## no NA
  lfmm.noNA <- lassoLFMM(K = 3, nozero.prop = 0.1)
  lfmm.noNA <- lfmm_fit(lfmm.noNA, dat)

  ## add na
  na.ind <- sample.int(n * p, 0.01 * n * p)
  dat$Y[na.ind] <- NA

  ## lfmm with na
  lfmm.NA <- lassoLFMM(K = 3, nozero.prop = 0.1)
  lfmm.NA <- lfmm_fit(lfmm.NA, dat)

  ## impute by median first
  dat$Y <- impute_median(dat$Y)
  lfmm.NA.impute <- lassoLFMM(K = 3, nozero.prop = 0.1)
  lfmm.NA.impute <- lfmm_fit(lfmm.NA.impute, dat)

  ## comparison W
  W.NA <- tcrossprod(lfmm.NA$U, lfmm.NA$V)
  W.noNA <- tcrossprod(lfmm.noNA$U, lfmm.noNA$V)
  W.NA.impute <- tcrossprod(lfmm.NA.impute$U, lfmm.NA.impute$V)
  e1 <- sqrt(mean((W.NA - W.noNA) ^ 2))
  e2 <- sqrt(mean((W.NA.impute - W.noNA) ^ 2))
  expect_gt((e2 - e1) / e1, 0.1)

  ## comparison B
  e1 <- sqrt(mean((lfmm.noNA$B - lfmm.NA$B) ^ 2))
  e2 <- sqrt(mean((lfmm.noNA$B - lfmm.NA.impute$B) ^ 2))
  expect_gt((e2 - e1) / e1, 0.1)

})


test_that("lassoLFMM with fixed lambda", {

  K <- 3
  dat <- lfmm_sampler(n = 100, p = 1000, K = K,
                      outlier.prop = 0.1,
                      cs = c(0.8),
                      sigma = 0.2,
                      B.sd = 1.0,
                      U.sd = 1.0,
                      V.sd = 1.0)
  dat.list <- list(G = dat$Y, X = dat$X)

  ## lassoLFMM
  m <- lassoLFMM(K = 3,
                 nozero.prop = NULL,
                 lambda.num = 1,
                 lambda.min.ratio = 0.001,
                 lambda = 0.5)
  m <- lfmm_fit(m, dat,
                                it.max = 100, relative.err.epsilon = 1e-4)

})
