context("test spltting analyses by segment")
library(GENESIS)
library(gdsfmt)
library(SeqVarTools)
library(Biobase)
library(dplyr)
library(GenomicRanges)

.testData <- function() {
    showfile.gds(closeall=TRUE, verbose=FALSE)
    gdsfile <- seqExampleFileName("gds")
    gds <- seqOpen(gdsfile)

    data(sample_annotation)
    SeqVarData(gds, sampleData=sample_annotation)
}

.testNullModel <- function(seqData, MM=FALSE) {
    if (MM) {
        data(grm)
        fitNullMM(sampleData(seqData), outcome="outcome", covars="sex", covMatList=grm, verbose=FALSE)
    } else {
        fitNullReg(sampleData(seqData), outcome="outcome", covars="sex", verbose=FALSE)
    }
}

.testSegFile <- function(segments) {
    seg.df <- as.data.frame(segments) %>%
        dplyr::rename(chromosome=seqnames) %>%
        dplyr::select(chromosome, start, end)
    segfile <- tempfile()
    write.table(seg.df, file=segfile, quote=FALSE, sep="\t", row.names=FALSE)
    segfile
}

test_that("single", {
    seqData <- .testData()
    nullmod <- .testNullModel(seqData, MM=TRUE)
    data(segments)
    segments <- segments[seqnames(segments) == 1]
    files <- character(length(segments))
    for (i in seq_along(segments)) {
        seqSetFilter(seqData, variant.sel=segments[i], verbose=FALSE)
        if (sum(seqGetFilter(seqData)$variant.sel) == 0) next
        assoc <- formatAssocSingle(seqData, assocTestMM(seqData, nullmod, verbose=FALSE))
        files[i] <- tempfile()
        save(assoc, file=files[i])
    }
    files <- setdiff(files, "")

    assoc <- combineAssoc(files, "single")

    seqResetFilter(seqData, verbose=FALSE)
    a <- formatAssocSingle(seqData, assocTestMM(seqData, nullmod, chromosome=1, verbose=FALSE))
    expect_equal(a, assoc)

    seqClose(seqData)
    unlink(files)
})


test_that("aggregate", {
    seqData <- .testData()
    nullmod <- .testNullModel(seqData)
    data(segments)
    segfile <- .testSegFile(segments)
    segments <- segments[seqnames(segments) == 1]
    
    id <- which(seqGetData(seqData, "chromosome") == 1)
    pos <- seqGetData(seqData, "position")[id]
    bins <- cut(id, breaks=10)
    varList <- lapply(levels(bins), function(x) {
        ind <- which(bins == x)
        data.frame(variant.id=ind, chromosome=1, position=pos[ind], allele.index=1)
    })
    files <- character(length(segments))
    for (i in seq_along(segments)) {
        vl <- subsetBySegment(varList, i, segfile)
        if (length(vl) == 0) next
        assoc <- assocTestSeq(seqData, nullmod, vl, verbose=FALSE)
        files[i] <- tempfile()
        save(assoc, file=files[i])
    }
    files <- setdiff(files, "")

    assoc <- combineAssoc(files, "aggregate")

    seqResetFilter(seqData, verbose=FALSE)
    a <- assocTestSeq(seqData, nullmod, varList, verbose=FALSE)
    expect_equal(a, assoc)

    seqClose(seqData)
    unlink(files)
    unlink(segfile)
})


test_that("window", {
    seqData <- .testData()
    nullmod <- .testNullModel(seqData)

    pos <- seqGetData(seqData, "position")[seqGetData(seqData, "chromosome") == 22]
    gr <- GRanges(seqnames=22, IRanges(start=pos, end=pos))
    size <- 1000
    shift <- 500
    segments <- GRanges(seqnames=22, ranges=IRanges(start=seq(1, max(pos), shift*1000), width=size*1.5*1000))
    segments <- subsetByOverlaps(segments, gr)
    
    segfile <- .testSegFile(segments)

    files <- character(length(segments))
    for (i in seq_along(segments)) {
        filterBySegment(seqData, i, segfile, pad.right=size*1000, verbose=FALSE)
        if (sum(seqGetFilter(seqData)$variant.sel) == 0) next
        id <- seqGetData(seqData, "variant.id")
        assoc <- assocTestSeqWindow(seqData, nullmod, variant.include=id, window.size=size, window.shift=shift, verbose=FALSE)
        files[i] <- tempfile()
        save(assoc, file=files[i])
    }
    files <- setdiff(files, "")

    assoc <- combineAssoc(files, "window")

    seqResetFilter(seqData, verbose=FALSE)
    a <- assocTestSeqWindow(seqData, nullmod, chromosome=22, window.size=size, window.shift=shift, verbose=FALSE)
    expect_equal(a, assoc)

    seqClose(seqData)
    unlink(files)
    unlink(segfile)
})