


ncatts <- function(x) {
  UseMethod("ncatts")
}

#' @importFrom ncdf4 ncatt_get
#' @importFrom stats setNames
#' @importFrom ncdf4 nc_open nc_close ncatt_get 
ncatts.character <- function(x) {
  on.exit(ncdf4::nc_close(ncf))
  ncf <- ncdf4::nc_open(x)
  global <- tibble::as_tibble(ncdf4::ncatt_get(ncf, 0))
  var <- setNames(vector('list', length(ncf$var)), names(ncf$var))
  childvar <- var
  for (vname in names(ncf$var)) {
    aaa <- ncatt_get(ncf, vname)
    lts <- lengths(aaa)
    if (length(unique(lts)) > 1) {
      tabs <- lapply(split(aaa, lts), tibble::as_tibble)
      var[[vname]] <- tabs[[1]]
      childvar[[vname]] <- tabs[-1]
    } 
    
  }
  ## childvar just a leftover for now
  ## drop all NULL
  list(global = global, var = var[!unlist(lapply(var, is.null))], childvar = childvar)
}


#' Information about a NetCDF file, in convenient form.
#'
#' [NetCDF] scans all the metadata provided by the [ncdf4::nc_open] function, and organizes it by the entities in the file. 
#' 
#' Users of 'NetCDF' files might be familiar with the command line tool 'ncdump
#' -h' noting that the "header" argument is crucial for giving a compact summary
#' of the contents of a file.  This package aims to provide that information
#' as data, to be used for writing code to otherwise access and manipulate the
#' contents of the files. This function doesn't do anything with the data, and
#' it doesn't access any of the data.
#' 
#' A NetCDF file contains the following entities, and each gets a data frame in the resulting object:  
#' \tabular{ll}{
#'  \code{attribute} \tab 'attributes' are general metadata about the file and its variables and dimensions\cr
#'  \code{dimension} \tab 'dimensions' are the axes defining the space of the data variables \cr
#'  \code{variable} \tab 'variables' are the actual data, the arrays containing data values \cr
#'  \code{group} \tab 'groups' are an internal abstraction to behave as a collection, analogous to a file. \cr
#'  }
#'  
#'  In addition to a data for each of the main entities above 'NetCDF' also creates:  
#'  \tabular{ll}{
#'  \code{unlimdims} \tab the unlimited dimensions identify those which are not a constant length (i.e. spread over files) \cr
#'  \code{dimvals} \tab a link table between dimensions and its coordinates \cr
#'  \code{file} \tab information about the file itself \cr
#'  \code{vardim} \tab a link table between variables and their dimensions \cr
#'  
#'  }
#'  
#'  Currently 'file' is expected to and treated as having only one row, but future versions may treat a collection of files 
#'  as a single entity. 
#'  
#'  The 'ncdump -h' print summary above is analogous to the print method [ncdf4::print.ncdf4] of the output of [ncdf4::nc_open]. 
#'  The approach here is under review, probably forever. https://github.com/hypertidy/ncdump/issues/8
#' @param x path to NetCDF file
#' @export
#' @importFrom ncdf4 nc_open
#' @importFrom rlang .data
#' @importFrom dplyr  bind_rows mutate 
#' @importFrom tibble as_tibble tibble
#' @seealso [ncdf4::nc_open] which is what this function uses to obtain the information 
#' @return A list of data frames with an unused S3 class 'NetCDF', see details for a description of the data frames. The 'attribute' 
#' data frame has class 'NetCDF_attributes', this is used with a custom print method to reduce the amount of output printed. 
#' @examples
#' rnc <- NetCDF(system.file("extdata", "S2008001.L3m_DAY_CHL_chlor_a_9km.nc", package= "ncdump"))
NetCDF <- function(x) {
  nc <- ncdf4::nc_open(x)
  dimension <- dplyr::bind_rows(lapply(nc$dim, function(x) tibble::as_tibble(x[!names(x) %in% c("dimvarid", "vals", "units", "calendar")])))
  unlimdims <- NULL
  if (any(dimension$unlim)) unlimdims <- dplyr::bind_rows(lapply( nc$dim[dimension$unlim], function(x) dplyr::tibble(x[names(x) %in% c("id", "vals", "units", "calendar")])))
  ## do we care that some dims are degenerate 1D?
  ##lapply(nc$dim, function(x) dim(x$vals))
  #split_if_character <- function(x) switch(mode(x), character = unlist(strsplit(x, "\\s+")), numeric = x)
  #null_if_char <- function(x) 
weird_char_dimvals <- unlist(lapply(nc$dim, function(x) is.character(x$vals)))
    dimension_values <- dplyr::bind_rows(
    lapply(nc$dim[!weird_char_dimvals], function(x) {
      ## some of these are matrices
      tibble::tibble(id = rep(x$id, length(x$vals)), vals = as.vector(x$vals))
    })
    )
  ## the dimids are in the dims table above
  group <- dplyr::bind_rows(lapply(nc$groups, function(x) tibble::as_tibble(x[!names(x) %in% "dimid"]))) 
  ## leave the fqgn2Rindex for now
  file <- tibble::as_tibble(nc[!names(nc) %in% c("dim", "var", "groups", "fqgn2Rindex")])
  ## when we drop these, how do we track keeping them elsewhere?
  variable <- dplyr::bind_rows(lapply(nc$var, function(x) tibble::as_tibble(x[!names(x) %in% c("chunksizes", "id", "dims", "dim", "missval", "varsize", "size", "dimids")])))
  variable$.variable_ <- sapply(nc$var, function(x) x$id$id)
  variable_link_dimension <- dplyr::bind_rows(lapply(nc$var, function(x) tibble::tibble(.variable_ = rep(x$id$id, length(x$dimids)), .dimension_ = x$dimids)))
  ## read attributes, should be made optional (?) to avoid long read time
  atts <- ncatts(x)
  class(atts) <- c("NetCDF_attributes", "list")
  ncdf4::nc_close(nc)
  
  ## create our IDs
  dimension <- dplyr::mutate(dimension, .dimension_  = .data$id,  .group_ = .data$group_id)
  ## TODO unlimdims
  dimension_values  <- dplyr::mutate(dimension_values, .dimension_ = .data$id)
  group  <- mutate(group, .group_  = .data$id)
  file    <- mutate(file, .file_ = .data$id) ##  (this should probably be replaced ?)
  variable  <- mutate(variable, .group_ = group$.group_[.data$group_index])
  
  
  x <- list(dimension = dimension, 
            unlimdims = unlimdims, 
            dimension_values = dimension_values, group = group, file = file, variable = variable, 
            vardim = variable_link_dimension, attribute = atts)
  class(x) <- c("ncdump", "list")
  x
}
#' @importFrom utils head
longlistformat <- function(x, n = 8) {
  if (length(x) <= n) return(x)
  paste(paste(head(x, n), collapse = ", "),  "...",  length(x) - n, "more ...")
}
#' @export
print.NetCDF_attributes <- function(x, ...) {
  print("NetCDF attributes:")
  print("Global")
  print("\n")
  print(x$global)
  print("\n")
  print("Variable attributes:")
  print(sprintf("variable attributes: %s", longlistformat(names(x$var))))
}

#' NetCDF file description functions. 
#' @param x NetCDF metadata object
#' @param ... ignored
#' @noRd
vars <- function(x, ...) UseMethod("vars")

#' @rdname vars
#' @noRd
vars.ncdump <- function(x, ...) {
  x$variable
}

#' @rdname vars
#' @noRd
dims <- function(x, ...) UseMethod("dims")
#' @rdname vars
#' @noRd
dims.ncdump <- function(x, ...) {
  x$dimension
}

#' @rdname vars
#' @noRd
dimvars <- function(x, ...) UseMethod("dimvars")

#' @rdname vars
#' @noRd
#' @importFrom dplyr %>% arrange_ filter filter_  inner_join select select_
dimvars.ncdump <- function(x, ...) {
  dmv <- (dims(x) %>% filter_("create_dimvar") %>% select_("name"))$name
  ndv <- length(dmv)
  ndims <- rep(0, ndv)
  tibble(name = dmv, 
         ndims = ndims, natts = ndims) 
  ## todo, how much is create_dimvar ncdf4 only?
  # prec = rep("float", ndv), 
  # units = rep("", ndv), 
  # longname = units, group_index = 
  # 
}


#' @param varname name of variable to get atts of (not yet implemented)
#'
#' @rdname vars
#' @noRd
atts <- function(x, ...) {
  UseMethod("atts")
}


#' @rdname vars
#' @noRd
atts.ncdump <- function(x, varname = "globalatts", ...) {
  if (varname == "globalatts") {
    x$attribute$global 
  } else {
    ## TODO, this needs thought given that childvar
    ## can be recursive and possible NULL
    stopifnot(varname %in% vars(x)$name)
    x$attribute$var[[varname]]
  }
}

#' @importFrom dplyr filter_
"[[.ncdump" <- function(x,i,j,...,drop=TRUE) {
  var <-  filter_(x$variable, .dots = list(~name == i))
  class(var) <- c("NetCDFVariable", class(var))
  var
}

#' @export
print.NetCDFVariable <- function(x, ...) {
  print(t(as.matrix(x)))
}

#' @export
"[.NetCDFVariable" <- function(x, i, j, ..., drop = TRUE) {
  # il <- lazy(i)
  # jl <- lazy(j)
  # dl <- lazy(...)
  #  print(dl)
  #  print( format(dl$expr))
  dots <- list(...)
  #  print(dots)
  ## this is ok, but also need array[i] type indexing, as well as array[matrix]
  if (missing(i)) stop("argument i must be provided")
  
  if (missing(j) & x$ndims > 1L) stop("argument j must be provided")
  #browser()
  nindex <- length(dots) + as.integer(!missing(i)) + as.integer(!missing(j))
  #print(nindex)
  if (!nindex == x$ndims) stop(sprintf("number of index elements must match dimensions of variable: %i", x$ndims))
  #print(i)
  ## now the hard work, see nchelper
  args <- c(list(i), if (missing(j)) list() else list(j), dots)
  # largs <- format(il$expr)
  #return(largs)
  # print(format(il$expr))
  #if (!missing(j)) largs <- sprintf("%s,%s", largs, format(jl$expr))
  
  #if (!missing(...)) sprintf(largs, format(dl$expr))
  # print('after')
  args
  # sprintf("%s[")
}


# nc <- NetCDF("data/mer_his_1992_01.nc")
# Cs_w <- nc[["Cs_w"]]
# lon_u <- nc[["lon_u"]]
# Cs_w[2]
# lon_u[2,3]
#
#