-- Create source table with settings keys from both global and site
DECLARE @settingsTable TABLE (
	KeyName nvarchar(100),
	KeyDisplayName nvarchar(200),
	KeyValue nvarchar(max),
	SiteID int,
	KeyCategoryID int,
	KeyOrder int,
	Rank bigint
)

-- Fill source table with settings keys
INSERT @settingsTable
SELECT
	KeyName, KeyDisplayName, KeyValue, SiteID, KeyCategoryID, KeyOrder,
	ROW_NUMBER() OVER (PARTITION BY KeyName ORDER BY SiteID desc) AS Rank
FROM 
	CMS_SettingsKey 
WHERE 
	(SiteID = (SELECT SiteID FROM CMS_Site WHERE SiteDomainName LIKE '%' + @domain + '%')
	OR SiteID IS NULL)
	AND
	KeyName IN (SELECT KeyName FROM @keyNames)

-- Select settings keys
SELECT 
	KeyCategoryID, SiteID, K.KeyName, KeyDisplayName, KeyValue, K.RecommendedValue, K.Notes 
FROM 
	(SELECT * FROM @settingsTable WHERE Rank = 1 ) S
RIGHT JOIN 
	@keyNames K 
ON
	S.KeyName = K.KeyName
ORDER BY 
	S.KeyOrder

-- Prepare where condition for category ID paths
DECLARE @categoryWhere nvarchar(max);
SELECT @categoryWhere =
		(
        SELECT DISTINCT
			'CategoryIDPath LIKE ''%' +  LTRIM(STR(KeyCategoryID)) + ''' OR '
		FROM 
			@settingsTable
        WHERE
			Rank = 1
        FOR XML PATH(''),TYPE).value('(text())[1]','VARCHAR(MAX)')
	
-- Fill category ID paths table with categories matching settings
DECLARE @categoryIdsTable TABLE (CategoryIDPath nvarchar(max))

INSERT INTO @categoryIdsTable
EXEC('SELECT CategoryIDPath FROM CMS_SettingsCategory WHERE '+ @categoryWhere +'(1=0)')

-- Select categories table
DECLARE @ORDERPADDING nvarchar(4)  = '000';
SELECT 
	CategoryID, CategoryDisplayName, CategoryName, CategoryIDPath, CategoryIsGroup, CategoryLevel, CategoryParentID
	,CASE 
		WHEN CategoryLevel = 0 THEN CONCAT(@ORDERPADDING,
										@ORDERPADDING, 
										@ORDERPADDING)

		WHEN CategoryLevel = 1 THEN CONCAT(
										FORMAT(CategoryOrder, @ORDERPADDING),
										@ORDERPADDING, 
										@ORDERPADDING)

		WHEN CategoryLevel = 2 THEN CONCAT(
										FORMAT((SELECT CategoryOrder FROM CMS_SettingsCategory WHERE CategoryID = S.CategoryParentID), @ORDERPADDING), 
										FORMAT(CategoryOrder, @ORDERPADDING),
										@ORDERPADDING)
									
		WHEN CategoryLevel = 3 THEN CONCAT(
										FORMAT((SELECT CategoryOrder FROM CMS_SettingsCategory WHERE CategoryID = (SELECT CategoryParentID FROM CMS_SettingsCategory WHERE CategoryID = S.CategoryParentID)), @ORDERPADDING),
										FORMAT((SELECT CategoryOrder FROM CMS_SettingsCategory WHERE CategoryID = S.CategoryParentID), @ORDERPADDING), 
										FORMAT(CategoryOrder, @ORDERPADDING))
	END AS NestedOrder
FROM 
	CMS_SettingsCategory S
WHERE 
 (SELECT DISTINCT
			CategoryIDPath + ''
		FROM 
			@categoryIdsTable
        FOR XML PATH(''),TYPE).value('(text())[1]','VARCHAR(MAX)')  LIKE '%' + FORMAT(CategoryID, '00000000') + '%'
ORDER BY 
	NestedOrder


