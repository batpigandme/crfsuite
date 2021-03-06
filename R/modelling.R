#' @title Linear-chain Conditional Random Field
#' @description Fits a Linear-chain (first-order Markov) CRF on the provided label sequence and saves it on disk in order to do sequence labelling.
#' @param x a character matrix of data containing attributes about the label sequence \code{y} or an object which can be coerced to a character matrix.
#' It is important to note that an attribute which has the same value in a different column is considered the same.
#' @param y a character vector with the sequence of labels to model
#' @param group an integer or character vector of the same length as \code{y} indicating the group the sequence \code{y} belongs to (e.g. a document or sentence identifier) 
#' @param method character string with the type of training method. Either one of:
#' \itemize{
#'  \item{lbfgs: }{L-BFGS with L1/L2 regularization}
#'  \item{l2sgd: }{SGD with L2-regularization}
#'  \item{averaged-perceptron: }{Averaged Perceptron}
#'  \item{passive-aggressive: }{Passive Aggressive}
#'  \item{arow: }{Adaptive Regularization of Weights (AROW)}
#' }
#' @param options a list of options to provide to the training algorithm. See \code{\link{crf_options}} for possible options and the example below on how to provide them.
#' @param file a character string with the path to the file on disk where the CRF model will be stored.
#' @param trace a logical indicating to show the trace of the training output. Defaults to \code{FALSE}.
#' @param FUN a function which can be applied on raw text in order to obtain the attribute matrix used in \code{predict.crf}. Currently not used yet.
#' @param ... arguments to FUN. Currently not used yet.
#' @return an object of class crf which is a list with elements
#' \itemize{
#'  \item{method: }{The training method}
#'  \item{type: }{The type of graphical model which is always set crf1d: Linear-chain (first-order Markov) CRF}
#'  \item{labels: }{The training labels}
#'  \item{options: }{A data.frame with the training options provided to the algorithm}
#'  \item{file_model: }{The path where the CRF model is stored}
#'  \item{attribute_names: }{The column names of \code{x}}
#'  \item{log: }{The training log of the algorithm}
#'  \item{FUN: }{The argument passed on to FUN}
#'  \item{ldots: }{A list with the arguments passed on to ...}
#' } 
#' @references More details about this model is available at \url{http://www.chokkan.org/software/crfsuite}.
#' @export
#' @seealso \code{\link{predict.crf}}
#' @examples 
#' ##
#' ## Build Named Entity Recognition model on tiny - 10 docs subset of conll2002-nl
#' ##
#' x         <- ner_download_modeldata("conll2002-nl", docs = 10)
#' x$pos     <- txt_sprintf("Parts of Speech: %s", x$pos)
#' x$token   <- txt_sprintf("Token: %s", x$token)
#' crf_train <- subset(x, data == "ned.train")
#' crf_test  <- subset(x, data == "testa")
#' 
#' model <- crf(y = crf_train$label, 
#'              x = crf_train[, c("token", "pos")], 
#'              group = crf_train$doc_id, 
#'              method = "lbfgs", 
#'              options = list(max_iterations = 3, feature.minfreq = 5, c1 = 0, c2 = 1)) 
#' model
#' stats <- summary(model, "modeldetails.txt")
#' stats
#' plot(stats$iterations$loss)
#' 
#' ## Use the CRF model to label a sequence
#' scores <- predict(model, 
#'                   newdata = crf_test[, c("token", "pos")], 
#'                   group = crf_test$doc_id)
#' head(scores)
#' crf_test$label <- scores$label
#' 
#' 
#' \dontrun{
#' ##
#' ## More detailed example where text data was annotated with the webapp in the package
#' ## This data is joined with a tokenised dataset to construct the training data which
#' ## is further enriched with attributes of upos/lemma in the neighbourhood
#' ##
#' library(udpipe)
#' data(airbnb_chunks, package = "crfsuite")
#' udmodel <- udpipe_download_model("dutch-lassysmall")
#' udmodel <- udpipe_load_model(udmodel$file_model)
#' airbnb_tokens <- unique(airbnb_chunks[, c("doc_id", "text")])
#' airbnb_tokens <- udpipe_annotate(udmodel, 
#'                                  x = airbnb_tokens$text, 
#'                                  doc_id = airbnb_tokens$doc_id)
#' airbnb_tokens <- as.data.frame(airbnb_tokens)
#' x <- merge(airbnb_chunks, airbnb_tokens)
#' x <- crf_cbind_attributes(x, terms = c("upos", "lemma"), by = "doc_id")
#' model <- crf(y = x$chunk_entity, 
#'              x = x[, grep("upos|lemma", colnames(x), value = TRUE)], 
#'              group = x$doc_id, 
#'              method = "lbfgs", options = list(max_iterations = 5)) 
#' stats <- summary(model)
#' stats
#' plot(stats$iterations$loss, type = "b", xlab = "Iteration", ylab = "Loss")
#' scores <- predict(model, 
#'                   newdata = x[, grep("upos|lemma", colnames(x))], 
#'                   group = x$doc_id)
#' head(scores)
#' 
#' ## cleanup for CRAN
#' file.remove(udmodel$file)
#' }
#' file.remove(model$file_model)
#' file.remove("modeldetails.txt")
crf <- function(x, y, group, 
                method = c("lbfgs", "l2sgd", "averaged-perceptron", "passive-aggressive", "arow"), 
                options = crf_options(method)$default, 
                file = "annotator.crfsuite", trace = FALSE, FUN = identity, ...){
  type <- "crf1d"
  file <- normalizePath(path.expand(file), mustWork = FALSE)
  trace <- as.integer(trace)
  method <- match.arg(method)
  x <- as.matrix(x)
  stopifnot(length(group) == length(y))
  stopifnot(nrow(x) == length(y))
  if(!is.integer(group)){
    group <- as.integer(factor(group))
  }
  options <- lapply(options, as.character)
  logfile <- tempfile(pattern = sprintf("CRFSUITE_TRAINER_LOG_RUN_%s_", tools::file_path_sans_ext(basename(file))), 
                      tmpdir = getwd(), fileext = ".log")
  Sys.setenv("CRFSUITE_TRAINER_LOG" = logfile)
  f <- Sys.getenv("CRFSUITE_TRAINER_LOG")
  if(trace){
    cat(sprintf("CRFsuite training progress logged to file %s", f), sep = "\n")
  }
  on.exit(file.remove(f))
  model <- crfsuite_model_build(file_model = file, 
                       doc_id = group, y = y, x = x,
                       options = options, method = method, type = type,
                       trace = trace)
  model$attribute_names <- colnames(x)
  model$log <- readLines(f)
  model$FUN <- FUN
  model$ldots <- list(...)
  class(model) <- "crf"
  if(trace){
    cat("CRFsuite training progress log file removed", sep = "\n")
  }
  model
}

#' @title Convert a model built with CRFsuite to an object of class crf
#' @description If you have a model built with CRFsuite either by this R package
#' or by another software library which wraps CRFsuite (e.g. Python/Java), you can 
#' convert it to an object of class \code{crf} which this package can use 
#' to inspect the model and to use it for prediction (if you can mimic the way the attributes are created).\cr
#' This is for expert use only.
#' @param file the path to a file on disk containing the CRFsuite model
#' @param ... other arguments which can be set except the path to the file, namely method, type, options, attribute_names, log (expert use only)
#' @return an object of class \code{crf}
#' @export
as.crf <- function(file, ...){
  ldots <- list(...)
  stopifnot(file.exists(file))
  object <- crfsuite_model(file)
  for(element in c("method", "type", "options", "attribute_names", "log", "FUN", "ldots")){
    object[[element]] <- ldots[[element]]
  }
  class(object) <- "crf"
  object
}

#' @export
print.crf <- function(x, ...){
  fsize <- file.info(x$file_model)$size
  cat(sprintf("Conditional Random Field saved at %s", x$file_model), sep = "\n")
  cat(sprintf("  size of the model in Mb: %s", round(fsize / (2^20), 2)), sep = "\n")
  cat(sprintf("  number of categories: %s", length(x$labels)), sep = "\n")
  cat(sprintf("  category labels: %s", paste(x$labels, collapse = ", ")), sep = "\n")
  cat(sprintf("To inspect the model in detail, summary(yourmodel, 'modeldetails.txt') and inspect the modeldetails.txt file", 
              deparse(substitute(x))), sep = "\n")
}


#' @export
summary.crf <- function(object, file, ...){
  stopifnot(file.exists(object$file_model))

  out <- list()
  out$active <- list()
  out$active$features <- as.numeric(gsub("(^Number of active features: )(.+) (.+)$", "\\2", grep("^Number of active features: ", object$log, value = TRUE)))
  out$active$attributes <- as.numeric(gsub("(^Number of active attributes: )(.+) (.+)$", "\\2", grep("^Number of active attributes: ", object$log, value = TRUE)))
  out$active$labels <- as.numeric(gsub("(^Number of active labels: )(.+) (.+)$", "\\2", grep("^Number of active labels: ", object$log, value = TRUE)))
  out$iterations <- list()
  out$iterations$nr <- grep("^\\*\\*\\*\\*\\* (Iteration)|(Epoch) #", object$log, value = TRUE)
  out$iterations$nr <- as.numeric(sapply(strsplit(out$iterations$nr, split = "#"), FUN=function(x) strsplit(tail(x, 1), " ")[[1]][1]))
  out$iterations$loss <- as.numeric(gsub("Loss: ", "", grep("^Loss: ", object$log, value=TRUE)))
  out$iterations$feature_norm <- as.numeric(gsub("Feature norm: ", "", grep("^Feature norm: ", object$log, value=TRUE)))
  out$iterations$error_norm <- as.numeric(gsub("Error norm: ", "", grep("^Error norm: ", object$log, value=TRUE)))
  out$iterations$active_features <- as.numeric(gsub("Active features: ", "", grep("^Active features: ", object$log, value=TRUE)))
  out$iterations$line_search_trials <- as.numeric(gsub("Line search trials: ", "", grep("^Line search trials: ", object$log, value=TRUE)))
  out$iterations$line_search_step <- as.numeric(gsub("Line search step: ", "", grep("^Line search step: ", object$log, value=TRUE)))
  out$iterations$feature_l2norm <- as.numeric(gsub("Feature L2-norm: ", "", grep("^Feature L2-norm: ", object$log, value=TRUE)))
  out$iterations$improvement_ratio <- as.numeric(gsub("Improvement ratio: ", "", grep("^Improvement ratio: ", object$log, value=TRUE)))
  out$iterations$learning_rate_eta <- as.numeric(gsub("Learning rate .+: ", "", grep("^Learning rate .+: ", object$log, value=TRUE)))
  out$iterations$feature_updates <- as.numeric(gsub("Total number of feature updates: ", "", grep("^Total number of feature updates: ", object$log, value=TRUE)))
  out$iterations$seconds <- as.numeric(gsub("Seconds required for this iteration: ", "", grep("^Seconds required for this iteration: ", object$log, value=TRUE)))
  out$iterations <- out$iterations[sapply(out$iterations, FUN=function(x) length(x) > 0)]
  out$last_iteration <- tail(grep("^\\*\\*\\*\\*\\* (Iteration)|(Epoch) #", object$log), 1)
  if(length(out$last_iteration) > 0){
    out$last_iteration <- tail(object$log, length(object$log) - out$last_iteration)
    out$last_iteration <- out$last_iteration[1:(head(which(out$last_iteration == ""), 1)-1)]
    cat("Summary statistics of last iteration: ", sep = "\n")
    cat(out$last_iteration, sep = "\n")  
  }
  
  tempfile <- tempfile(pattern = "crfsuite_", fileext = ".txt")
  cat(sprintf("\nDumping summary of the model to file %s", tempfile), sep = "\n")
  crfsuite_model_dump(object$file_model, tempfile)
  if(!missing(file)){
    cat(sprintf("Copying summary of the model to file %s in folder %s", file, ifelse(basename(file) == file, getwd(), dirname(file))), sep = "\n")
    file.copy(from = tempfile, to = file, overwrite = TRUE)  
  }
  invisible(out)
}


#' @title Predict the label sequence based on the Conditional Random Field
#' @description Predict the label sequence based on the Conditional Random Field
#' @param object an object of class crf as returned by \code{\link{crf}}
#' @param newdata a character matrix of data containing attributes about the label sequence \code{y} or an object which can be coerced to a character matrix. 
#' This data should be provided in the same format as was used for training the model
#' @param group an integer or character vector of the same length as nrow \code{newdata} indicating the group the sequence \code{y} belongs to (e.g. a document or sentence identifier) 
#' @param type either 'marginal' or 'sequence' to get predictions at the level of \code{newdata} or a the level of the sequence \code{group}. Defaults to \code{'marginal'}
#' @param trace a logical indicating to show the trace of the labelling output. Defaults to \code{FALSE}.
#' @param ... not used
#' @export
#' @return 
#' If \code{type} is 'marginal': a data.frame with columns label and marginal containing the viterbi decoded predicted label and marginal probability. \cr
#' If \code{type} is 'sequence': a data.frame with columns group and probability containing for each sequence group the probability of the sequence.
#' @seealso \code{\link{crf}}
#' @examples 
#' \dontrun{
#' library(udpipe)
#' data(airbnb_chunks, package = "crfsuite")
#' udmodel <- udpipe_download_model("dutch-lassysmall")
#' udmodel <- udpipe_load_model(udmodel$file_model)
#' airbnb_tokens <- unique(airbnb_chunks[, c("doc_id", "text")])
#' airbnb_tokens <- udpipe_annotate(udmodel, 
#'                                  x = airbnb_tokens$text, 
#'                                  doc_id = airbnb_tokens$doc_id)
#' airbnb_tokens <- as.data.frame(airbnb_tokens)
#' x <- merge(airbnb_chunks, airbnb_tokens)
#' x <- crf_cbind_attributes(x, terms = c("upos", "lemma"), by = "doc_id")
#' model <- crf(y = x$chunk_entity, 
#'              x = x[, grep("upos|lemma", colnames(x))], 
#'              group = x$doc_id, 
#'              method = "lbfgs", options = list(max_iterations = 5)) 
#' scores <- predict(model, 
#'                   newdata = x[, grep("upos|lemma", colnames(x))], 
#'                   group = x$doc_id, type = "marginal")
#' head(scores)
#' scores <- predict(model, 
#'                   newdata = x[, grep("upos|lemma", colnames(x))], 
#'                   group = x$doc_id, type = "sequence")
#' head(scores)
#' 
#' 
#' ## cleanup for CRAN
#' file.remove(model$file_model)
#' file.remove("modeldetails.txt")
#' file.remove(udmodel$file)
#' }
predict.crf <- function(object, newdata, group, type = c("marginal", "sequence"), trace = FALSE, ...){
  stopifnot(file.exists(object$file_model))
  trace <- as.integer(trace)
  newdata <- as.matrix(newdata)
  stopifnot(nrow(newdata) == length(group))
  type <- match.arg(type)
  if(!is.integer(group)){
    recodegroup <- TRUE
    group <- factor(group)
    levs <- levels(group)
    group <- as.integer(group)
  }else{
    recodegroup <- FALSE
  }
  scores <- crfsuite_predict(file_model = object$file_model, doc_id = group, x = newdata, trace = trace)
  if(type == "marginal"){
    scores <- scores$viterbi
  }else if(type == "sequence"){
    scores <- scores$sequence
    if(recodegroup){
      scores$group <- levs[match(scores$group, table = seq_along(levs))]
    }
  }
  scores
}


#' @title Conditional Random Fields parameters
#' @description Conditional Random Fields parameters
#' @param method character string with the type of training method. Either one of:
#' \itemize{
#'  \item{lbfgs: }{L-BFGS with L1/L2 regularization}
#'  \item{l2sgd: }{SGD with L2-regularization}
#'  \item{averaged-perceptron: }{Averaged Perceptron}
#'  \item{passive-aggressive: }{Passive Aggressive}
#'  \item{arow: }{Adaptive Regularization of Weights (AROW)}
#' }
#' @return a list with elements 
#' \itemize{
#'  \item{method: }{The training method}
#'  \item{type: }{The type of graphical model which is always set crf1d: Linear-chain (first-order Markov) CRF}
#'  \item{params: }{A data.frame with fields arg, arg_default and description indicating the possible hyperparameters of the algorithm, the default values and the description}
#'  \item{default: }{A list of default values which can be used to pass on to the \code{options} argument of \code{\link{crf}}}
#' }
#' @export
#' @examples 
#' # L-BFGS with L1/L2 regularization
#' opts <- crf_options("lbfgs")
#' str(opts)
#' 
#' # SGD with L2-regularization
#' crf_options("l2sgd")
#' 
#' # Averaged Perceptron
#' crf_options("averaged-perceptron")
#' 
#' # Passive Aggressive
#' crf_options("passive-aggressive")
#' 
#' # Adaptive Regularization of Weights (AROW)
#' crf_options("arow")
crf_options <- function(method = c("lbfgs", "l2sgd", "averaged-perceptron", "passive-aggressive", "arow")){
  type <- "crf1d"
  method <- match.arg(method)
  params <- crfsuite_model_parameters(method, type)
  params$default <- structure(as.list(params$params$arg_default), 
                              .Names = params$params$arg)
  params$default <- lapply(params$default, FUN=function(x){
    suppressWarnings({
      value <- as.numeric(x) 
      value <- ifelse(is.na(value), x, value)
    })
    value
  })
  params
}


