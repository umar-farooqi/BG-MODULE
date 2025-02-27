-- NEW BI REPORT QUERY 
WITH BANK_NAME AS (
    SELECT 
        ASM.SR_ID,
        AST.REG_NAME
    FROM 
        AB_SETUP_REGISTRATION ASM
    JOIN 
        AB_SETUP_REGISTRATION AST 
        ON AST.SR_ID = ASM.SR_IDS AND AST.REG_TYPE = 'BANK'
    WHERE 
        ASM.REG_TYPE = 'BANK LOV'
        AND ASM.ORG_ID = :GV_ORG_ID
    ORDER BY 
        ASM.CREATED_ON DESC
), QUERY1 AS (
    SELECT 
        AFL.BANK_ID,
        AFLD.FACILITIES_ID,
        BN.REG_NAME,
        MAX(CASE 
            WHEN ALD.DET_ID = AFLD.FACILITIES_ID AND ALD.LOOKUP_ID = '032' THEN ALD.LOOKUP_DET_NAME 
            ELSE NULL 
        END) AS FACILITIES_NAME,
        NVL(SUM(AFLD.AMOUNT), 0) AS AMOUNT
    FROM 
        AB_FACILITIES_LETTER AFL
    LEFT JOIN 
        AB_FACILITIES_LETTER_DET AFLD  
        ON AFLD.MAST_ID = AFL.ID
    LEFT JOIN 
        AB_LOOKUP_DETAIL ALD 
        ON ALD.DET_ID = AFLD.FACILITIES_ID
    LEFT JOIN 
        BANK_NAME BN 
        ON BN.SR_ID = AFL.BANK_ID
    WHERE 
        AFL.FACILITIES_TYPE = 'FACILITIES MAST'
        AND AFL.ORG_ID = NVL(:GV_ORG_ID, AFL.ORG_ID)
    GROUP BY 
        AFL.BANK_ID, AFLD.FACILITIES_ID, BN.REG_NAME
), QUERY2 AS (
    SELECT
        AFL.BANK_ID,
        AFL.FACILITIES_ID,
        AFL.MATURITY_TYPE,
        NVL(SUM(AFL.AMOUNT), 0) AS AVAILED,
        AFL.BG_EXPIRE_DATE
    FROM 
        AB_FACILITIES_LETTER AFL
    LEFT JOIN 
        AB_FACILITIES_LETTER_DET AFLD 
        ON AFLD.MAST_ID = AFL.ID
    LEFT JOIN 
        AB_LOOKUP_DETAIL ALD 
        ON ALD.DET_ID = AFL.FACILITIES_ID
    WHERE 
        AFL.FACILITIES_TYPE = 'LIMIT UTILIZATION'
        AND AFL.ORG_ID = NVL(:GV_ORG_ID, AFL.ORG_ID)
    GROUP BY 
        AFL.BANK_ID, AFL.FACILITIES_ID, AFL.BG_EXPIRE_DATE, AFL.MATURITY_TYPE
), INITIAL_DATA AS (
    SELECT 
        Q1.BANK_ID,
        Q1.REG_NAME AS BANK_NAME, -- Corrected alias for bank name
        Q1.FACILITIES_NAME,
        Q2.MATURITY_TYPE,
        NVL(Q1.AMOUNT, 0) AS AMOUNT_NON,
        NVL(Q2.AVAILED, 0) AS AVAILED_NON,
        Q2.BG_EXPIRE_DATE,
        ROW_NUMBER() OVER (PARTITION BY Q1.BANK_ID ORDER BY Q1.FACILITIES_NAME) AS RN
    FROM 
        QUERY1 Q1
    LEFT JOIN 
        QUERY2 Q2 
        ON Q1.BANK_ID = Q2.BANK_ID
        AND Q1.FACILITIES_ID = Q2.FACILITIES_ID
    WHERE 
        Q2.MATURITY_TYPE = 'NON FINANCIAL'
), RECURSIVE_CTE (BANK_ID, BANK_NAME, FACILITIES_NAME, MATURITY_TYPE, AMOUNT_NON, AVAILED_NON, BALANCE_NON, BG_EXPIRE_DATE, RN) AS (
    -- Base case: first row
    SELECT 
        BANK_ID,
        BANK_NAME, -- Properly reference BANK_NAME here
        FACILITIES_NAME,
        MATURITY_TYPE,
        AMOUNT_NON,
        AVAILED_NON,
        (AMOUNT_NON - AVAILED_NON) AS BALANCE_NON,
        BG_EXPIRE_DATE,
        RN
    FROM 
        INITIAL_DATA
    WHERE 
        RN = 1

    UNION ALL

    -- Recursive calculation for subsequent rows
    SELECT 
        ID.BANK_ID,
        NULL AS BANK_NAME, -- Do not propagate BANK_NAME for other rows
        ID.FACILITIES_NAME,
        ID.MATURITY_TYPE,
        REC.BALANCE_NON AS AMOUNT_NON, -- Use previous BALANCE_NON as current AMOUNT_NON
        ID.AVAILED_NON,
        (REC.BALANCE_NON - ID.AVAILED_NON) AS BALANCE_NON,
        ID.BG_EXPIRE_DATE,
        ID.RN
    FROM 
        RECURSIVE_CTE REC
    JOIN 
        INITIAL_DATA ID 
        ON REC.BANK_ID = ID.BANK_ID
        AND REC.RN + 1 = ID.RN -- Link current row with the next row
)
SELECT 
    BANK_ID,
    CASE 
        WHEN ROW_NUMBER() OVER (PARTITION BY BANK_ID ORDER BY RN) = 1 THEN BANK_NAME
        ELSE NULL
    END AS BANK_NAME, -- Ensure BANK_NAME appears only once for each BANK_ID
    FACILITIES_NAME,
    MATURITY_TYPE,
    AMOUNT_NON,
    AVAILED_NON,
    BALANCE_NON,
    BG_EXPIRE_DATE
FROM 
    RECURSIVE_CTE
ORDER BY 
    BANK_ID, RN DESC;
