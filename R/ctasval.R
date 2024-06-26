#' Prepare SDTM LB Data
#'
#' This function prepares the LB (Laboratory) data for SDTM (Study Data Tabulation Model) by merging it with the DM (Demographics) data.
#'
#' @param lb Data frame containing the LB data.
#' @param dm Data frame containing the DM data.
#' @param scramble Logical indicating whether to scramble the SITEID in the DM data. Default is TRUE.
#' @return A data frame with the prepared SDTM LB data.
#' @export
prep_sdtm_lb <- function(lb, dm, scramble = TRUE) {
  if (scramble) {
    dm$SITEID <- sample(
      dm$SITEID,
      replace = FALSE,
      size = length(dm$SITEID)
    )
  }

  df_prep <- lb %>%
    mutate(
      timepoint_rank = .data$VISITNUM,
      timepoint_1_name = as.character(.data$VISIT),
      result = .data$LBSTRESN,
      parameter_id = .data$LBTEST,
      parameter_name = .data$LBTEST,
      timepoint_2_name = "no",
      baseline = NA,
      parameter_category_1 = .data$LBCAT
    ) %>%
    inner_join(
      dm %>%
        distinct(.data$USUBJID, .data$SITEID),
      by = c("USUBJID")
    ) %>%
    rename(c(
      subject_id = "USUBJID",
      site = "SITEID"
    ))

  return(df_prep)
}

#' Prepare SDTM VS Data
#'
#' This function prepares the VS (Vital Sign) data for SDTM (Study Data Tabulation Model) by merging it with the DM (Demographics) data.
#'
#' @param vs Data frame containing the VS data.
#' @param dm Data frame containing the DM data.
#' @param scramble Logical indicating whether to scramble the SITEID in the DM data. Default is TRUE.
#' @return A data frame with the prepared SDTM LB data.
#' @export
prep_sdtm_vs <- function(vs, dm, scramble = TRUE) {
  if (scramble) {
    dm$SITEID <- sample(
      dm$SITEID,
      replace = FALSE,
      size = length(dm$SITEID)
    )
  }

  df_prep <- vs %>%
    mutate(
      timepoint_rank = .data$VISITNUM,
      timepoint_1_name = as.character(.data$VISIT),
      result = .data$VSSTRESN,
      parameter_id = .data$VSTEST,
      parameter_name = .data$VSTEST,
      timepoint_2_name = "no",
      baseline = NA,
      parameter_category_1 = rep("no categories",length.out=length(.data$VSTEST))
    ) %>%
    inner_join(
      dm %>%
        distinct(.data$USUBJID, .data$SITEID),
      by = c("USUBJID")
    ) %>%
    rename(c(
      subject_id = "USUBJID",
      site = "SITEID"
    ))

  return(df_prep)
}

#' Get CTAS
#'
#' This function processes a study using the CTAS (Clinical Trial Anomaly Spotter) by providing various parameters and features.
#'
#' @param df Data frame containing the study data.
#' @param feats Features to calculate for the timeseries.
#' @param default_minimum_timepoints_per_series Minimum timepoints per series. Default is 3.
#' @param default_minimum_subjects_per_series Minimum subjects per series. Default is 3.
#' @param default_max_share_missing_timepoints_per_series Maximum share of missing timepoints per series. Default is 0.5.
#' @param default_generate_change_from_baseline Logical indicating whether to generate change from baseline. Default is FALSE.
#' @param autogenerate_timeseries Logical indicating whether to auto-generate timeseries. Default is TRUE.
#' @return A data frame with the CTAS results.
#' @keywords internal
#' @seealso \code{\link{get_anomaly_scores}}
get_ctas <- function(df, feats,
                     default_minimum_timepoints_per_series = 3,
                     default_minimum_subjects_per_series = 3,
                     default_max_share_missing_timepoints_per_series = 0.5,
                     default_generate_change_from_baseline = FALSE,
                     autogenerate_timeseries = TRUE) {

  parameters <- df %>%
    distinct(
      .data$parameter_id,
      .data$parameter_name,
      .data$parameter_category_1
    ) %>%
    mutate(
      parameter_category_2 = "no",
      parameter_category_3 = "no",
      time_point_count_min = NA,
      subject_count_min = NA,
      max_share_missing = NA,
      generate_change_from_baseline = NA,
      timeseries_features_to_calculate = NA,
      use_only_custom_timeseries = FALSE # should have datatype check
    )

  subjects <- df %>%
    distinct(.data$subject_id, .data$site) %>%
    mutate(
      country = "no",
      region = "no"
    )

  data <- df %>%
    select(c(
      "subject_id",
      "parameter_id",
      "timepoint_1_name",
      "timepoint_2_name",
      "timepoint_rank",
      "result",
      "baseline"
    ))

  ls_ctas <- ctas::process_a_study(
    data = data,
    subjects = subjects,
    parameters = parameters,
    custom_timeseries = ctas::ctas_data$custom_timeseries,
    custom_reference_groups = ctas::ctas_data$custom_reference_groups,
    default_timeseries_features_to_calculate = feats,
    default_minimum_timepoints_per_series = default_minimum_timepoints_per_series,
    default_minimum_subjects_per_series = default_minimum_subjects_per_series,
    default_max_share_missing_timepoints_per_series = default_max_share_missing_timepoints_per_series,
    default_generate_change_from_baseline = default_generate_change_from_baseline,
    autogenerate_timeseries = autogenerate_timeseries
  )

  data_ctas_prep <- ls_ctas$site_scores %>%
    left_join(ls_ctas$timeseries, by = "timeseries_id") %>%
    summarise(
      score = max(.data$fdr_corrected_pvalue_logp),
      .by = c("site", "parameter_id")
    )

  data_ctas <- df %>%
    distinct(.data$site, .data$parameter_id) %>%
    left_join(
      data_ctas_prep,
      by = c("site", "parameter_id")
    ) %>%
    mutate(
      score = ifelse(is.na(.data$score), 0, .data$score)
    )

  return(data_ctas)
}

#' Sample Site Data
#'
#' This function samples one random site per parameter from the given data frame.
#'
#' @param df Data frame containing the study data.
#' @param site The site to sample from. Default is "sample_site".
#' @return A data frame with the sampled site data.
#' @keywords internal
#' @seealso \code{\link{anomaly_average}}, \code{\link{anomaly_sd}}
sample_site <- function(df, site = "sample_site") {

  df_n_sites <- df %>%
    summarise(
      n_pat_site_param = n_distinct(.data$subject_id),
      .by = c("site", "parameter_id")
    ) %>%
    slice_sample(n = 1, by = "parameter_id") %>%
    select(c("parameter_id", "n_pat_site_param"))

  subject_id <- unique(df$subject_id)

  subj_rdn_id <- sample(
    seq(1, length(subject_id)),
    length(subject_id),
    replace = FALSE
  )

  names(subj_rdn_id) <- subject_id

  df_sample_site <- df %>%
    mutate(
      subject_random = subj_rdn_id[.data$subject_id]
    ) %>%
    mutate(
      subject_random = dense_rank(.data$subject_random),
      .by = "parameter_id"
    ) %>%
    left_join(
      df_n_sites,
      by = "parameter_id"
    ) %>%
    filter(.data$subject_random <= .data$n_pat_site_param) %>%
    mutate(
      site = .env$site,
      subject_id = paste0(.data$site, "-", .data$subject_id)
    ) %>%
    select(- c("subject_random", "n_pat_site_param"))

  return(df_sample_site)
}



#' Generate Anomaly Data
#'
#' This function generates anomaly data by applying a specified anomaly function to the data frame.
#'
#' @param df Data frame containing the study data.
#' @param n_sites Number of sites to generate.
#' @param fun_anomaly Function to apply to generate anomalies.
#' @param anomaly_degree Degree of anomaly to add.
#' @param site_prefix Prefix for the site names. Default is "site".
#' @return A data frame with the generated anomaly data.
#' @keywords internal
#' @seealso \code{\link{get_anomaly_scores}}
get_anomaly_data <- function(df, n_sites, fun_anomaly, anomaly_degree, site_prefix = "site") {

  grid <- tibble(
    site_anomaly = paste0(site_prefix, seq(1, n_sites))
  ) %>%
    mutate(
      site_data = purrr::map(
        .data$site_anomaly,
        ~ fun_anomaly(
          df = df,
          anomaly_degree = anomaly_degree,
          site = .
        )
      )
    )

  df_anomaly <- bind_rows(df, grid$site_data) %>%
    mutate(
      method = max(.data$method, na.rm = TRUE)
    )

  return(df_anomaly)
}

#' Get Anomaly Scores
#'
#' This function calculates the scores for anomalies in the data frame.
#'
#' @param df Data frame containing the study data.
#' @param n_sites Number of sites to generate.
#' @param fun_anomaly Function to apply to generate anomalies.
#' @param anomaly_degree Degree of anomaly to add.
#' @param feats Features to calculate for the timeseries.
#' @param thresh Threshold for classification. Default is NULL.
#' @param default_minimum_timepoints_per_series Minimum timepoints per series. Default is 3.
#' @param default_minimum_subjects_per_series Minimum subjects per series. Default is 3.
#' @param default_max_share_missing_timepoints_per_series Maximum share of missing timepoints per series. Default is 0.5.
#' @param default_generate_change_from_baseline Logical indicating whether to generate change from baseline. Default is FALSE.
#' @param autogenerate_timeseries Logical indicating whether to auto-generate timeseries. Default is TRUE.
#' @return A data frame with the anomaly scores.
#' @keywords internal
#' @seealso \code{\link{ctasval}}
get_anomaly_scores <- function(df, n_sites, fun_anomaly, anomaly_degree, feats, thresh = NULL,
                               default_minimum_timepoints_per_series = 3,
                               default_minimum_subjects_per_series = 3,
                               default_max_share_missing_timepoints_per_series = 0.5,
                               default_generate_change_from_baseline = FALSE,
                               autogenerate_timeseries = TRUE) {

  df_anomaly <- get_anomaly_data(
    df = df,
    n_sites = n_sites,
    fun_anomaly = fun_anomaly,
    anomaly_degree = anomaly_degree,
    site_prefix = "sample_site"
  )

  df_ctas <- get_ctas(
    df = df_anomaly,
    feats = feats,
    default_minimum_timepoints_per_series = default_minimum_timepoints_per_series,
    default_minimum_subjects_per_series = default_minimum_subjects_per_series,
    default_max_share_missing_timepoints_per_series = default_max_share_missing_timepoints_per_series,
    default_generate_change_from_baseline = default_generate_change_from_baseline,
    autogenerate_timeseries = autogenerate_timeseries
  ) %>%
    mutate(
      is_P = startsWith(.data$site, "sample_site")
    )

  if (!is.null(thresh)) {
    df_thresh <- df_ctas %>%
      mutate(
        classification = case_when(
          .data$is_P & .data$score >= thresh ~ "TP",
          .data$is_P & .data$score < thresh ~ "FN",
          .data$score >= thresh ~ "FP",
          TRUE ~ "TN"
        ),
        classification = factor(.data$classification, levels = c("TP", "FN", "FP", "TN"))
      ) %>%
      summarise(
        n = n_distinct(.data$site),
        .by = c("parameter_id", "classification"),
      ) %>%
      complete(.data$classification, .data$parameter_id, fill = list(n = 0)) %>%
      pivot_wider(names_from = "classification", values_from = "n", values_fill = 0)

    df_result <- df_thresh
  } else {
    df_result <- df_ctas
  }

  df_anomaly_filt <- df_anomaly %>%
    filter(startsWith(.data$site, "sample_site")) %>%
    left_join(
      df_ctas %>%
        distinct(.data$site, .data$parameter_id, .data$score),
        by = c("site", "parameter_id")
    )

  structure(
    list(
      result = df_result,
      anomaly = df_anomaly_filt
    ),
    class = "ctasval_single"
  )
}

#' CTAS Validation
#'
#' This function performs CTAS validation by generating anomalies, calculating scores, and summarizing performance metrics.
#'
#' @param df Data frame containing the study data.
#' @param fun_anomaly List of functions to apply to generate anomalies.
#' @param feats List of features to calculate for the timeseries.
#' @param anomaly_degree Vector of anomaly degrees to add. Default is c(0, 0.5, 1, 5, 10, 50).
#' @param thresh Threshold for classification. Default is 1.0.
#' @param iter Number of iterations to run. Default is 100.
#' @param n_sites Number of sites to generate. Default is 3.
#' @param parallel Logical indicating whether to run in parallel. Default is FALSE.
#' @param progress Logical indicating whether to show progress. Default is TRUE.
#' @param default_minimum_timepoints_per_series Minimum timepoints per series. Default is 3.
#' @param default_minimum_subjects_per_series Minimum subjects per series. Default is 3.
#' @param default_max_share_missing_timepoints_per_series Maximum share of missing timepoints per series. Default is 0.5.
#' @param default_generate_change_from_baseline Logical indicating whether to generate change from baseline. Default is FALSE.
#' @param autogenerate_timeseries Logical indicating whether to auto-generate timeseries. Default is TRUE.
#' @return A list containing the performance metrics and anomaly data.
#' @export
#' @examples
#' df_prep <- prep_sdtm_lb(pharmaversesdtm::lb, pharmaversesdtm::dm, scramble = TRUE)
#'
#' df_filt <- df_prep %>%
#'   filter(parameter_id == "Alkaline Phosphatase")
#'
#' ctas <- ctasval(
#'   df = df_filt,
#'   fun_anomaly = c(anomaly_average, anomaly_sd),
#'   feats = c("average", "sd"),
#'   parallel = FALSE,
#'   iter = 1
#' )
#'
#' ctas
#'
ctasval <- function(df,
                    fun_anomaly,
                    feats,
                    anomaly_degree = c(0, 0.5, 1, 5, 10, 50),
                    thresh = 1.0,
                    iter = 100,
                    n_sites = 3,
                    parallel = FALSE,
                    progress = TRUE,
                    default_minimum_timepoints_per_series = 3,
                    default_minimum_subjects_per_series = 3,
                    default_max_share_missing_timepoints_per_series = 0.5,
                    default_generate_change_from_baseline = FALSE,
                    autogenerate_timeseries = TRUE) {
  stopifnot("Each 'fun_anomaly' must be paired with one 'feats'" = length(fun_anomaly) == length(feats))

  df_grid <- tibble(
    iter = seq(1, iter),
    anomaly_degree = list(anomaly_degree),
    fun_anomaly = list(tibble(fun_anomaly = fun_anomaly, feats = feats))
  ) %>%
    unnest(anomaly_degree) %>%
    unnest(fun_anomaly)

  if (parallel) {
    fun_purrr <- furrr::future_pmap
    purrr_args <- list(.options = furrr::furrr_options(seed = TRUE))
  } else {
    fun_purrr <- purrr::pmap
    purrr_args <- list()

  }

  simaerep::with_progress_cnd(
    df_result <- df_grid %>%
      mutate(
        ctas = simaerep::purrr_bar(
          list(fun_anomaly, anomaly_degree, feats),
          .purrr = fun_purrr,
          .f = function(x, y, z, ...) get_anomaly_scores(fun_anomaly = x, anomaly_degree = y, feats = z, ...),
          .f_args = list(
            df = .env$df,
            thresh = thresh,
            n_sites = n_sites,
            default_minimum_timepoints_per_series = default_minimum_timepoints_per_series,
            default_minimum_subjects_per_series = default_minimum_subjects_per_series,
            default_max_share_missing_timepoints_per_series = default_max_share_missing_timepoints_per_series,
            default_generate_change_from_baseline = default_generate_change_from_baseline,
            autogenerate_timeseries = autogenerate_timeseries
          ),
          .purrr_args = purrr_args,
          .steps = nrow(df_grid),
          .progress = progress
        )
      ),
    progress = progress
  )

  df_perf <- df_result %>%
    mutate(ctas = map(.data$ctas, "result")) %>%
    unnest("ctas") %>%
    summarise(
      across(c("TN", "FN", "FP", "TP"),
             ~ sum(., na.rm = TRUE)),
      .by = c("anomaly_degree", "feats", "parameter_id")
    ) %>%
    rowwise() %>%
    mutate(
      tpr = .data$TP / (.data$TP + .data$FN),
      fpr = .data$FP / (.data$FP + .data$TN)
    ) %>%
    ungroup()

  df_anomaly <- df_result %>%
    mutate(ctas = map(.data$ctas, "anomaly")) %>%
    unnest("ctas")

  structure(
    list(
      result = df_perf,
      anomaly = df_anomaly
    ),
    class = "ctasval_aggregated"
  )
}
