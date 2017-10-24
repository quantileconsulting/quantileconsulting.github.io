{-# LANGUAGE OverloadedStrings #-}
import Hakyll
import Data.Monoid ((<>))
import Data.List (stripPrefix)
import qualified Data.Set as Set
import Hakyll.Web.Sass (sassCompiler)
import Hakyll.Favicon (faviconsRules, faviconsField)


main :: IO ()
main = hakyllWith hakyllConfig $ do
  faviconsRules "images/favicon.svg"

  match (fromGlob "images/**" .||. fromGlob "js/**" .||. fromGlob "lib/**") $ do
    route idRoute
    compile copyFileCompiler

  match "css/*.scss"$ do
    route $ setExtension "css"
    compile (fmap compressCss <$> sassCompiler)

  match (fromList [ "pages/about.markdown"
                  , "pages/imprint.markdown"
                  , "pages/LICENSE.markdown"
                  ]) $ do
    route $
      customRoute (maybe (error "Expected pages to be in 'pages' folder")
                         id . stripPrefix "pages/" . toFilePath)
      `composeRoutes` setExtension "html"
    let
      pageCtx =
        faviconsField <> defaultContext
    compile $ pandocCompiler
      >>= loadAndApplyTemplate "templates/page.html" pageCtx
      >>= loadAndApplyTemplate "templates/default.html" pageCtx
      >>= relativizeUrls

  tags <- buildTags "posts/**" (fromCapture "tags/*.html")
  createTagsRules tags (\xs -> "Posts tagged \"" ++ xs ++ "\"")

  categories <- buildCategories "posts/**" (fromCapture "categories/*.html")
  createTagsRules categories (\xs -> "Posts categorised as \"" ++ xs ++ "\"")

  match "posts/**" $ do
    route $ setExtension "html"
    let
      namedTags =
        [("tags", tags), ("categories", categories)]
    compile $ pandocCompiler
      >>= saveSnapshot "content"
      >>= loadAndApplyTemplate "templates/post.html" (ctxWithTags postCtx namedTags)
      >>= loadAndApplyTemplate "templates/default.html" (ctxWithTags postCtx namedTags)
      >>= relativizeUrls

  match "pages/index.html" $ do
    route (constRoute "index.html")
    compile $ do
      posts <- recentFirst =<< loadAll "posts/**"
      let
        indexCtx =
          listField "posts" postCtx (return posts)
          <> constField "title" "Home"
          <> faviconsField
          <> defaultContext
      getResourceBody
        >>= applyAsTemplate indexCtx
        >>= loadAndApplyTemplate "templates/default.html" indexCtx
        >>= relativizeUrls

  match (fromGlob "partials/*" .||. fromGlob "templates/*") $
    compile templateBodyCompiler

  create ["feed.xml"] $ do
    route idRoute
    compile $ do
      let
        feedCtx =
          postCtx <> bodyField "description"
      posts <- fmap (take 10) . recentFirst =<< loadAllSnapshots "posts/**" "content"
      renderAtom atomFeedConfiguration feedCtx posts

  -- SEO-related stuff
  create ["sitemap.xml"] $ do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll "posts/**"
      pages <- loadAll "pages/*"
      let
        crawlPages =
          sitemapPages pages ++ posts
        sitemapCtx =
          mconcat [ listField "entries" defaultContext (return crawlPages)
                  , defaultContext
                  ]
      makeItem ""
        >>= loadAndApplyTemplate "templates/sitemap.xml" sitemapCtx
        >>= relativizeUrls

  match (fromList ["robots.txt", "CNAME"]) $ do
    route idRoute
    compile $ getResourceBody >>= relativizeUrls

  match "pages/google3f1f5a1db3d4b0ba.html" $ do
    route (constRoute "google3f1f5a1db3d4b0ba.html")
    compile $ getResourceBody >>= relativizeUrls


ctxWithTags :: Context String -> [(String, Tags)] -> Context String
ctxWithTags ctx =
  foldr (\(name, tags) baseCtx -> tagsField name tags <> baseCtx) ctx


postCtx :: Context String
postCtx =
    dateField "date" "%B %e, %Y"
    <> teaserField "teaser" "content"
    -- create a short version of the teaser. Strip out HTML tags and trim.
    <> mapContext (trim . take 160 . stripTags) (teaserField "teaser-short" "content")
    <> faviconsField
    <> defaultContext
  where
    trim xs =
      map snd . filter trim' $ zip [0..] xs
      where
        trim' (ix, x)
          | ix == 0 || ix == (length xs - 1) =
              x `notElem` [' ' , '\n', '\t']
          | otherwise =
              True


createTagsRules :: Tags -> (String -> String) -> Rules ()
createTagsRules tags mkTitle =
  tagsRules tags $ \tag pattern -> do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll pattern
      let
        ctx =
          constField "title" (mkTitle tag)
          <> listField "posts" postCtx (return posts)
          <> faviconsField
          <> defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/tag.html" ctx
        >>= loadAndApplyTemplate "templates/default.html" ctx
        >>= relativizeUrls


atomFeedConfiguration :: FeedConfiguration
atomFeedConfiguration =
  FeedConfiguration { feedTitle       = "Futtetennismo"
                    , feedDescription = ""
                    , feedAuthorName  = "futtetennista"
                    , feedAuthorEmail = "futtetennista@gmail.com"
                    , feedRoot        = "https://futtetennismo.me"
                    }


hakyllConfig :: Configuration
hakyllConfig =
  defaultConfiguration{ previewHost = "0.0.0.0" }


sitemapPages :: [Item String] -> [Item String]
sitemapPages =
  filter ((/="pages/LICENSE.markdown") . toFilePath . itemIdentifier)