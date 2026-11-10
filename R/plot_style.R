# Copied from the COHERO RCT analysis (github.com/VagishHemmige/COHERO-RCT-analysis,
#   R/plot_style.R at commit e8c4fa5, 2026-11-09), the maintainer's house
#   style for figures. Unchanged except this note and the reference to where
#   the theme is set as the default (report_figures.R here).

# Purpose: the house style for figures: a publication theme with its color,
#   shape and line-type palettes, readable labels for variables, and one way
#   to save a figure at print size. Reads no global objects and changes no
#   settings when loaded, so it can be copied into another project together
#   with functions.R; this project sets the theme as the default in
#   report_figures.R.
# Needs: ggplot2 4.0.0 or later (palettes carried by the theme, labels by
#   dictionary); installed: scales, svglite, ragg.
# Produces: theme_publication(), label_figure(), figure_label(),
#   save_figure(), publication_colors.

## ---- check-ggplot2-version
if (utils::packageVersion("ggplot2") < "4.0.0") {
  stop(
    "The figures need ggplot2 4.0.0 or later; this R has ggplot2 ",
    utils::packageVersion("ggplot2"), ". Update it with install.packages()."
  )
}

## ---- publication-palettes
# Okabe-Ito colors (safe for the common kinds of color-vision deficiency),
# with a neutral dark gray first: the first group of any factor, such as the
# control arm or a reference level, is drawn in gray and the second in blue
okabe_ito <- unname(grDevices::palette.colors(palette = "Okabe-Ito"))
publication_colors <- c("#555555", okabe_ito[c(6, 7, 4, 2, 8, 3, 5)])

# Shapes and line types differ too, so groups never rely on color alone.
# Filled shapes 21-25 take a white fill, so overlapping points stay visible.
publication_shapes <- c(21, 24, 22, 23, 25)
publication_linetypes <- c("22", "solid", "42", "12", "4212")

## ---- theme-publication
# A quiet theme for print: no panel border, light horizontal gridlines only,
# thin axis lines, text sized for the printed figure. The legend sits above
# the panel; figures that name their groups on the plot itself remove it.
theme_publication <- function(base_size = 9, base_family = "",
                              header_family = NULL) {
  ggplot2::theme_minimal(
    base_size = base_size,
    base_family = base_family,
    header_family = header_family
  ) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(
        color = "gray90", linewidth = 0.3
      ),
      axis.line.x = ggplot2::element_line(color = "gray30", linewidth = 0.3),
      axis.ticks.x = ggplot2::element_line(color = "gray30", linewidth = 0.3),
      axis.title = ggplot2::element_text(color = "gray20"),
      axis.text = ggplot2::element_text(color = "gray30"),
      strip.text = ggplot2::element_text(face = "bold", hjust = 0),
      plot.title = ggplot2::element_text(face = "bold"),
      plot.title.position = "plot",
      plot.caption = ggplot2::element_text(color = "gray35", hjust = 0),
      plot.caption.position = "plot",
      legend.position = "top",
      legend.justification = "left",
      palette.color.discrete = publication_colors,
      palette.fill.discrete = publication_colors,
      palette.shape.discrete = scales::pal_manual(publication_shapes),
      palette.linetype.discrete = publication_linetypes
    )
}

## ---- label-figure
# Axis and legend titles from labels (readable names, named by variable), so
# no raw column name reaches a figure; arm names (named by level) in place of
# their codes in the legend and, with arm_axis = TRUE, on an arm x-axis
label_figure <- function(labels, arm_labels, arm_axis = FALSE) {
  layers <- list(
    ggplot2::labs(dictionary = labels),
    ggplot2::scale_color_discrete(labels = arm_labels)
  )
  if (arm_axis) {
    layers <- c(layers, list(ggplot2::scale_x_discrete(labels = arm_labels)))
  }
  layers
}

# One variable's readable label from labels, or its name when it has none
figure_label <- function(variable, labels = NULL) {
  if (variable %in% names(labels)) {
    unname(labels[[variable]])
  } else {
    variable
  }
}

## ---- save-figure
# Save a figure at its printed size, in millimetres: PDF (cairo, which embeds
# fonts and handles symbols such as the dagger) and SVG for journals, PNG
# (ragg) for the website. Returns the paths written.
save_figure <- function(plot, file, width, height,
                        formats = c("pdf", "svg", "png"), dpi = 600) {
  devices <- list(
    pdf = grDevices::cairo_pdf,
    svg = svglite::svglite,
    png = ragg::agg_png
  )
  paths <- paste0(file, ".", formats)
  for (i in seq_along(formats)) {
    ggplot2::ggsave(
      paths[i], plot,
      device = devices[[formats[i]]],
      width = width, height = height, units = "mm", dpi = dpi,
      bg = "white"
    )
  }
  invisible(paths)
}
