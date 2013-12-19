summaryP <- function(formula, data=NULL,
                     subset=NULL, na.action=na.retain,
                     exclude1=TRUE, sort=TRUE,
                     asna=c('unknown', 'unspecified')) {
  
  formula <- Formula(formula)
  environment(formula) <- new.env(parent = environment(formula))
  Asna <- asna
  Sort <- sort
  yn <- function(..., label=deparse(substitute(...)), asna=Asna, sort=Sort) {
    w <- list(...)
    k <- length(w)
    if(! k) stop('no variables to process')
    nam <- as.character(sys.call())[-1]
    nam <- nam[1 : k]
    lab <- nam
    W <- matrix(NA, nrow=length(w[[1]]), ncol=k, dimnames=list(NULL, nam))
    for(j in 1:k) {
      x <- w[[j]]
      na <- is.na(x)
      la <- label(x)
      if(la != '') lab[j] <- la
      if(is.numeric(x) && all(x %in% 0 : 1)) x <- x == 1
      if(! is.logical(x)) {
        x <- tolower(as.character(x))
        if(length(asna)) {
          i <- x %in% asna
          if(any(i)) na[i] <- TRUE
        }
        x <- x %in% c('y', 'yes', 'present')
        if(any(na)) x[na] <- NA
      }
      W[, j] <- x
    }
    ## Sort columns in ascending order of overall proportion
    prop <- apply(W, 2, mean, na.rm=TRUE)
    if(sort) {
      i <- order(prop)
      W <- W[, i, drop=FALSE]
      lab <- lab[i]
    }
    structure(W, label=label, labels=lab, class=c('yn', 'matrix'))
  }
  assign(envir = environment(formula), 'yn', yn)
  '[.yn' <- function(x, ...) {
    at <- attributes(x)[c('label', 'labels')]
    x <- NextMethod('[')
    attributes(x) <- c(attributes(x), at)
    class(x) <- 'yn'
    x
  }
  
  lhs <- terms(formula, lhs=1, specials='yn')
  rhs <- terms(formula, rhs=1)
  cl <- attr(lhs, 'specials')
  
  Y <- if(length(subset))
    model.frame(formula, data=data, subset=subset, na.action=na.action)
  else
    model.frame(formula, data=data, na.action=na.action)
  X <- model.part(formula, data=Y, rhs=1)
  Y <- model.part(formula, data=Y, lhs=1)

  nY <- NCOL(Y)
  nX <- NCOL(X)
  namY <- names(Y)
  if(nX == 0) X <- data.frame(x=rep(1, NROW(Y)))
  ux <- unique(X)
  Z <- NULL
  n <- nrow(X)

  if(Sort) {
    ## Compute marginal frequencies of all regular variables so can sort
    mfreq <- list()
    for(ny in namY) {
      y <- Y[[ny]]
      if(!inherits(y, 'yn')) {
        if(length(asna) && (is.factor(y) || is.character(y)))
          y[y %in% asna] <- NA
        freq <- table(y)
        counts        <- as.numeric(freq)
        names(counts) <- names(freq)
        mfreq[[ny]]   <- - sort(- counts)
      }
    }
  }
  for(i in 1 : nrow(ux)) {
    j <- rep(TRUE, n)
    if(nX > 0) for(k in 1 : nX) j <- j & (X[[k]] == ux[i, k])
    ## yx <- Y[j,, drop=FALSE]
    for(k in 1 : nY) {
      ## y <- yx[[k]] doesn't work as attributes lost by [.data.frame
      y <- Y[[k]]
      y <- if(is.matrix(y)) y[j,, drop=FALSE] else y[j]
#      y <- (Y[[k]])[j,, drop=FALSE]
      if(inherits(y, 'yn')) {
        overlab <- attr(y, 'label')
        labs <- attr(y, 'labels')
        z <- NULL
        for(iy in 1 : ncol(y)) {
          tab <- table(y[, iy])
          z <- rbind(z,
                     data.frame(var=overlab, val=labs[iy],
                                freq=as.numeric(tab['TRUE']),
                                denom=as.numeric(sum(tab))))
        }
      }
      else {  # regular single column
        if(length(asna) && (is.factor(y) || is.character(y)))
          y[y %in% asna] <- NA
        tab <- table(y)
        ny <- namY[k]
        la  <- label(y)
        if(la == '') la <- ny
        lev <- names(tab)
        mf <- mfreq[[ny]]
        if(exclude1 && length(mf) == 2) {
          lowest <- names(which.min(mf))
          z <- data.frame(var=la, val=lowest,
                          freq=as.numeric(tab[lowest]),
                          denom=as.numeric(sum(tab)))
        }
        else {
          if(Sort) lev <- reorder(lev, (mfreq[[ny]])[lev])
          z <- data.frame(var=la, val=lev,
                          freq=as.numeric(tab),
                          denom=as.numeric(sum(tab)))
        }
      }
      ## Add current X subset settings
      if(nX > 0) for(k in 1: nX) z[[names(ux)[k]]] <- ux[i, k]
      Z <- rbind(Z, z)
    }
  }
  structure(Z, class=c('summaryP', 'data.frame'), formula=formula, nX=nX, nY=nY)
}

plot.summaryP <-
  function(x, formula=NULL, groups=NULL, xlim=c(0, 1), col=1:2, pch=1:2,
           cex.values=0.5, xwidth=.125, ydelta=0.04,
           key=list(columns=length(levels(groups)),
             x=.75, y=-.04, cex=.9, col=col, corner=c(0,1)), outerlabels=TRUE, ...)
{
  if(outerlabels) require(latticeExtra)
  X <- x
  at <- attributes(x)
  Form <- at$formula
  nX   <- at$nX
  nY   <- at$nY
  groupsname <- as.character(substitute(groups))
  if(length(groupsname)) groups <- x[[groupsname]]
  
  condvar <- setdiff(names(X), c('val', 'var', 'freq', 'denom', groupsname))
  form <- if(length(formula)) formula
  else {
    form <- paste('val ~ freq | var')
    if(length(condvar))
      form <- paste(form, paste(condvar, collapse=' * '), sep=' * ')
    as.formula(form)
  }
  
  pan <- function(x, y, subscripts, groups=NULL, col, ...) {
    y <- as.numeric(y)
    denom <- X$denom[subscripts]
    prop <- x / denom
    panel.dotplot(x/denom, y, subscripts=subscripts, groups=groups, ...)
    if(length(cex.values) && cex.values > 0) {
      xl <- current.panel.limits()$xlim
      xdel <- 0.025 * diff(xl)
      yl <- current.panel.limits()$ylim
      ydel <- ydelta * diff(yl)
      txt <- if(length(groups)) {
        groups <- groups[subscripts]
        tx <- ''
        ig <- 0
        xw <- xwidth * diff(xl)
        xpos <- xl[2] - xdel - length(levels(groups)) * xw
        for(g in levels(groups)) {
          ig <- ig + 1
          i <- groups == g
          fr <- paste(x[i], denom[i], sep='/')
          xpos <- xpos + xw
          ltext(xpos, y - ydel, fr, cex=cex.values,
                col=col[ig], adj=1)
        }
      }
      else {
        fr <- paste(x, denom, sep='/')
        ltext(xl[2] - 0.025 * diff(xl), y - ydel, fr,
              cex=cex.values, col=col[1], adj=1)
      }
    }
  }
  if(length(groupsname))
    trellis.par.set(superpose.symbol = list(col = col, pch=pch))
  else
    trellis.par.set(dot.symbol = list(col = col[1], pch=pch[1]))
  d <- if(length(groupsname))
    sprintf("dotplot(form, groups=%s, data=X, scales=list(y='free', rot=0), panel=pan, xlim=xlim, auto.key=key, xlab='Proportion', col=col)", groupsname)
  else sprintf("dotplot(form, data=X, scales=list(y='free', rot=0), panel=pan, xlim=xlim, auto.key=key, xlab='Proportion', col=col[1])")
  d <- eval(parse(text = d))

  if(outerlabels && (nX - length(groupsname) + 1) == 2)
    d <- useOuterStrips(d)
  d
}