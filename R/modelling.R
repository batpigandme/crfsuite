#' @title Linear-chain Conditional Random Field
#' @description Fits a Linear-chain (first-order Markov) CRF on the provided label sequence and saves it on disk in order to do sequence labelling.
#' @param x a character matrix of data containing attributes about the label sequence \code{y} or an object which can be coerced to a character matrix
#' @param y a character vector with the sequence of labels to model
#' @param group an integer vector of the same length as \code{y} indicating the group the sequence \code{y} belongs to (e.g. a document or sentence identifier) 
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
#' @return an object of class crf which is a list with elements
#' \itemize{
#'  \item{file_model: }{The path where the CRF model is stored}
#'  \item{labels: }{The training labels}
#'  \item{attribute_names: }{The column names of \code{x}}
#' } 
#' @references More details about this model is available at \url{http://www.chokkan.org/software/crfsuite}.
#' @export
#' @examples 
#' ## Get some training data
#' x <- ner_download_modeldata("conll2002-nl")
#' crf_train <- subset(x, data == "ned.train")
#' crf_test <- subset(x, data == "testa")
#' 
#' ## Build the CRF model
#' model <- crf(y = crf_train$label, x = crf_train[, c("token", "pos")], 
#'              group = crf_train$doc_id, 
#'              method = "lbfgs", options = list(max_iterations = 5), trace = TRUE) 
#' model
#' summary(model, "modeldetails.txt")
#' 
#' ## Use the CRF model to label a sequence
#' scores <- predict(model, 
#'                   newdata = crf_test[, c("token", "pos")], group = crf_test$doc_id)
#' head(scores)
#' table(scores$label == crf_test$label)
#' 
#' ## cleanup for CRAN
#' file.remove(model$file_model)
#' file.remove("modeldetails.txt")
crf <- function(x, y, group, 
                method = c("lbfgs", "l2sgd", "averaged-perceptron", "passive-aggressive", "arow"), 
                options = crf_options(method)$default, 
                file = "annotator.crfsuite", trace = FALSE){
  type <- "crf1d"
  file <- normalizePath(path.expand(file), mustWork = FALSE)
  trace <- as.integer(trace)
  method <- match.arg(method)
  x <- as.matrix(x)
  stopifnot(length(group) == length(y))
  stopifnot(nrow(x) == length(y))
  options <- lapply(options, as.character)
  model <- crfsuite_model_build(file_model = file, 
                       doc_id = group, y = y, x = x,
                       options = options, method = method, type = type,
                       trace = trace)
  model$attribute_names <- colnames(x)
  class(model) <- "crf"
  model
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
  tempfile <- tempfile(pattern = "crfsuite_", fileext = ".txt")
  cat(sprintf("dumping summary of the model to file %s", tempfile), sep = "\n")
  crfsuite_model_dump(object$file_model, tempfile)
  if(!missing(file)){
    cat(sprintf("copying summary of the model to file %s", file), sep = "\n")
    file.copy(from = tempfile, to = file, overwrite = TRUE)  
  }
  invisible()
}


#' @title Predict the label sequence based on the Conditional Random Field
#' @description Predict the label sequence based on the Conditional Random Field
#' @param object an object of class crf as returned by \code{\link{crf}}
#' @param newdata a character matrix of data containing attributes about the label sequence \code{y} or an object which can be coerced to a character matrix. 
#' This data should be provided in the same format as was used for training the model
#' @param group an integer vector of the same length as nrow \code{newdata} indicating the group the sequence \code{y} belongs to (e.g. a document or sentence identifier) 
#' @param type either 'marginal' or 'sequence' to get predictions at the level of \code{newdata} or a the level of the sequence \code{group}. Defaults to \code{'marginal'}
#' @param trace a logical indicating to show the trace of the labelling output. Defaults to \code{FALSE}.
#' @param ... not used
#' @export
#' @return 
#' If \code{type} is 'marginal': a data.frame with columns label and marginal containing the viterbi decoded predicted label and marginal probability. \cr
#' If \code{type} is 'sequence': a data.frame with columns group and probability containing for each sequence group the probability of the sequence.
#' @seealso \code{\link{crf}}
predict.crf <- function(object, newdata, group, type = c("marginal", "sequence"), trace = FALSE, ...){
  stopifnot(file.exists(object$file_model))
  trace <- as.integer(trace)
  newdata <- as.matrix(newdata)
  stopifnot(nrow(newdata) == length(group))
  type <- match.arg(type)
  scores <- crfsuite_predict(file_model = object$file_model, doc_id = group, x = newdata, trace = trace)
  if(type == "marginal"){
    scores <- scores$viterbi
  }else if(type == "sequence"){
    scores <- scores$sequence
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